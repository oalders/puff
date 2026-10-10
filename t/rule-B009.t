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

run_corpus('B009');

my @classes = Puff::Rules->load;
my ($class) = grep { $_->code eq 'B009' } @classes;

sub violations ($text) {
    my $result = Puff::Engine->new( rules => [ $class->new ] )
        ->process_source( Puff::Source->from_string($text), file => 'x.pl' );
    return $result->{violations};
}

is(
    [ map { $_->message } @{ violations("my \$s = sprintf '%s: %d', \$x;\n") } ],
    ['Missing argument in sprintf: format expects 2, got 1'],
    'missing argument message'
);
is(
    [ map { $_->message } @{ violations("printf \"%s\\n\", \$x, \$y;\n") } ],
    ['Redundant argument in printf: format expects 1, got 2'],
    'redundant argument message'
);
is(
    [ map { $_->message } @{ violations("CORE::sprintf '%s';\n") } ],
    ['Missing argument in sprintf: format expects 1, got 0'],
    'CORE:: is dropped from the name'
);
my $found = violations("my \$s = sprintf '%s';\n");
is( [ map { $_->column } @$found ], [9], 'reported at the function name' );
is( [ map { $_->fixable ? 1 : 0 } @$found ], [0], 'no fix is offered' );
is( $class->fix_safety, 'none', 'fix safety is none' );

sub selected (@select) {
    return [ grep { $_ eq 'B009' } map { $_->code } Puff::Rules->instantiate( \@classes, select => [@select] ) ];
}
is( selected( 'S', 'B' ), [], 'not selected by the default prefixes' );
is( selected('B00'), [], 'not selected by a longer prefix' );
is( selected('B009'), ['B009'], 'selected by its exact code' );
is( selected('ALL'), ['B009'], 'selected by ALL' );

# Through the CLI: the prefix B does not enable the rule, its code does.
my $root = path(getcwd)->absolute;
my @puff = (
    $^X, '-I' . $root->child('lib'), '-I' . $root->child( 'local', 'lib', 'perl5' ),
    $root->child( 'bin', 'puff' )->stringify, 'check', '--no-config',
);
my $dir  = tempdir();
my $file = $dir->child('x.pl');
$file->spew_utf8("my \$x;\nmy \$s = sprintf '%s %s', \$x;\n");
my $out = run_capture( undef, @puff, '--select', 'B', "$file" );
unlike( $out, qr/B009/, '--select B does not enable B009' );
$out = run_capture( undef, @puff, '--select', 'B009', "$file" );
like( $out, qr/:2:\d+: B009 Missing argument in sprintf/, '--select B009 enables it' );
is( $? >> 8, 1, 'and exits 1' );

done_testing;
