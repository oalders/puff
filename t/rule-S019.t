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
