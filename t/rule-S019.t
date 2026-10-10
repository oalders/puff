use v5.36;
use Test2::V0;

use lib 't/lib';
use TestCommand qw( run_capture );

use Cwd        qw( getcwd );
use Path::Tiny qw( path tempdir );

use Puff::Engine ();
use Puff::Rules  ();
use Puff::Source ();
use Puff::Test   qw( run_corpus );

run_corpus('S019');

my @classes = Puff::Rules->load;
my ($class) = grep { $_->code eq 'S019' } @classes;

sub violations ($text) {
    my $result = Puff::Engine->new( rules => [ $class->new ] )
        ->process_source( Puff::Source->from_string($text), file => 'x.pl' );
    return $result->{violations};
}

is(
    [
        map { [ $_->line, $_->column, $_->message, $_->fixable ] }
            @{ violations("/\$x|\$y->{k}/;\nqr{\n  a \$z[0]\n}x;\n") }
    ],
    [
        [ 1, 2, '$x interpolated into a regex without \Q...\E; metacharacters in it change the match', 1 ],
        [ 1, 5, '$y->{k} interpolated into a regex without \Q...\E; metacharacters in it change the match', 1 ],
        [ 3, 5, '$z[0] interpolated into a regex without \Q...\E; metacharacters in it change the match', 0 ],
    ],
    'each variable is reported at its own line and column'
);
my $msg = '$x interpolated into a regex without \Q...\E; metacharacters in it change the match; no fix: ';
is(
    [ map { [ $_->message, $_->fixable ] } @{ violations("/\$x+/;\n/[\$x]/;\n/a # \$x\n  \$x/x;\n/\${x}{k}/;\n") } ],
    [
        [ $msg . 'a quantifier follows it, and after \Q...\E it would apply to the last character only', 0 ],
        [ $msg . 'it is inside a character class', 0 ],
        [ $msg . 'it is inside a /x comment', 0 ],
        [ $msg =~ s/; no fix: \z//r, 1 ],
        [ ( $msg =~ s/\A\$x/\${x}/r ) =~ s/; no fix: \z//r, 1 ],
    ],
    'no fix, with the reason, after a quantifier, in a class or in a /x comment; ${x} ends at the brace'
);

# A qr// assigned in another sub does not hide the variable; one in an
# enclosing block does.
is(
    [
        map { $_->line } @{
            violations("sub a { my \$t = qr/x/ }\nsub b { my \$t = shift; /\$t/ }\nmy \$u = qr/x/;\nsub c { /\$u/ }\n")
        }
    ],
    [2],
    'the qr// assignment must be visible from the use'
);

# A write through a package-qualified name may be to the `our` variable.
is(
    [
        map { $_->line } @{
            violations(
                "our \$x = qr/a/;\n\$main::x = shift;\n/\$x/;\nour \$y = qr/a/;\n\$::y = shift;\n/\$y/;\nour \$z = qr/a/;\n/\$z/;\n"
            )
        }
    ],
    [ 3, 6 ],
    'a package-qualified write counts'
);

# The cost is linear in the number of declarations, variables and fixes.
# Element locations and parents are counted, as timings would be flaky.
{
    no warnings 'redefine';
    my %calls;
    for my $method (qw( location parent )) {
        my $orig = PPI::Element->can($method);
        no strict 'refs';
        *{"PPI::Element::$method"} = sub { $calls{$method}++; goto &$orig };
    }
    my $count = sub ($text) {
        my $doc = PPI::Document->new( \$text );
        $doc->index_locations;
        my @regexes = @{ $doc->find('PPI::Token::Regexp::Match') };
        %calls = ();
        $class->new->check( $_, $doc ) for @regexes;
        return { %calls, regexes => scalar @regexes };
    };

    my $decls = $count->( join q{}, map {"my \$x = qr/a/;\n/\$x/;\n"} 1 .. 400 );
    cmp_ok( $decls->{location}, '<', 10 * $decls->{regexes}, 'locations: linear in the declarations' );

    my $nested = $count->( ( "my \$x if do { /\$x/;\n" x 100 ) . ( "1 };\n" x 100 ) );
    cmp_ok( $nested->{parent}, '<', 2 * 100**2, 'parents: quadratic, not cubic, in the nesting depth' );

    # Before the fix, _findings ran once per violation.
    my $findings = 0;
    my $orig     = \&Puff::Rule::Security::RegexInterpolation::_findings;
    *Puff::Rule::Security::RegexInterpolation::_findings = sub { $findings++; goto &$orig };
    my $result = Puff::Engine->new( rules => [ $class->new ], fix_mode => q{unsafe} )
        ->process_source( Puff::Source->from_string( '/' . ( '$x' x 50 ) . "/;\n" ), file => 'x.pl' );
    is( $result->{fixed_count}, 50, q{every variable is fixed} );
    ok( $findings < 10, "the findings of a regex are computed once per pass ($findings)" );
    *Puff::Rule::Security::RegexInterpolation::_findings = $orig;
}

# A regex over many lines with many variables is scanned once, not once per
# variable. It took over 15 seconds before; the bound is loose for slow hosts.
{
    my $start = time;
    my $found = violations( "/\n" . ( "\$x\n" x 20_000 ) . "/x;\n" );
    is( scalar @$found, 20_000, 'every variable in a long regex is reported' );
    is( [ $found->[-1]->line, $found->[-1]->column ], [ 20_001, 1 ], 'at its line and column' );
    cmp_ok( time - $start, '<', 6, 'in linear time' );
}

is( $class->fix_safety, 'unsafe', 'fix safety is unsafe' );
is( [ $class->cwe ], [ 625, 1333 ], 'CWE categories' );

sub selected (@select) {
    return [ grep { $_ eq 'S019' } map { $_->code } Puff::Rules->instantiate( \@classes, select => [@select] ) ];
}
is( selected( 'S', 'B' ), [], 'not selected by the default prefixes' );
is( selected('S01'), [], 'not selected by a longer prefix' );
is( selected('S019'), ['S019'], 'selected by its exact code' );
is( selected('ALL'), ['S019'], 'selected by ALL' );

# Through the CLI: the defaults and the prefix S do not enable the rule, its
# code and ALL do.
my $root = path(getcwd)->absolute;
my @puff = (
    $^X, '-I' . $root->child('lib'), '-I' . $root->child( 'local', 'lib', 'perl5' ),
    $root->child( 'bin', 'puff' )->stringify, 'check', '--no-config',
);
my $dir  = tempdir();
my $file = $dir->child('x.pl');
$file->spew_utf8("my \$x = 1;\nprint 1 if 'a' =~ /\$x/;\n");
my $out = run_capture( undef, @puff, "$file" );
unlike( $out, qr/S019/, 'not enabled by default' );
$out = run_capture( undef, @puff, '--select', 'S', "$file" );
unlike( $out, qr/S019/, '--select S does not enable S019' );
$out = run_capture( undef, @puff, '--select', 'S019', "$file" );
like( $out, qr/:2:20: S019 \$x interpolated into a regex/, '--select S019 enables it' );
is( $? >> 8, 1, 'and exits 1' );
$out = run_capture( undef, @puff, '--select', 'ALL', "$file" );
like( $out, qr/S019/, '--select ALL enables it' );

done_testing;
