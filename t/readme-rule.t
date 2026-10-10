use v5.36;
use Test2::V0;

use lib 't/lib';
use TestCommand qw( run_capture );

# Checks the example rule in the README ("Writing a rule"). The README shows
# t/lib-rules/NoFixme.pm verbatim, so this test keeps the example working.

use Cwd        qw( getcwd );
use Path::Tiny qw( path tempdir );
use Puff::Test qw( run_corpus );

my $root = path(getcwd)->absolute;
my @PERL = ( $^X, '-I' . $root->child('lib'), '-I' . $root->child( 'local', 'lib', 'perl5' ) );
my $PUFF = $root->child( 'bin', 'puff' )->stringify;
my $RULE = $root->child( 't', 'lib-rules', 'NoFixme.pm' );

sub puff ( $dir, @args ) {
    my $orig = getcwd;
    chdir $dir or die "chdir $dir: $!";
    my $out  = run_capture( undef, @PERL, $PUFF, @args );
    my $exit = $? >> 8;
    chdir $orig or die "chdir $orig: $!";
    return ( $out, $exit );
}

# An absolute rule-paths entry is used as it is.
my $dir    = tempdir();
my $config = sprintf qq{rule-paths = ["%s"]\nextend-select = ["X"]\n}, $RULE->parent;
$dir->child('.puff.toml')->spew_utf8($config);
$dir->child('a.pl')->spew_utf8("# FIXME: tidy\nprint 1;      # FIXME later\n");
my $readme = $root->child('README.md')->slurp_utf8;

my ( $out, $exit ) = puff( $dir, 'check', 'a.pl' );
is( $exit, 1, 'violations found' );
like( $out, qr{^a\.pl:1:1: X001 Use TODO instead of FIXME \[\*\]$}m, 'first comment reported' );
like( $out, qr{^a\.pl:2:15: X001 Use TODO instead of FIXME \[\*\]$}m, 'second comment reported' );

( $out, $exit ) = puff( $dir, 'rule', 'X001' );
is( $exit, 0, 'rule X001 explained' );
like( $out, qr{^X001: Use TODO instead of FIXME\nFix safety: safe\n}, 'rule header' );

( $out, $exit ) = puff( $dir, 'check', '--fix', 'a.pl' );
is( $exit, 0, 'clean after the safe fix' );
is( $dir->child('a.pl')->slurp_utf8, "# TODO: tidy\nprint 1;      # TODO later\n", 'comments rewritten' );

$dir->child('b.pl')->spew_utf8("# NOTE: x\n# KEEP this\n");
$dir->child('.puff.toml')->spew_utf8( $config . qq{[rules.X001]\nkeyword = "KEEP"\n} );
( $out, $exit ) = puff( $dir, 'check', 'b.pl' );
like( $out, qr{^b\.pl:2:1: X001 Use TODO instead of KEEP}m, 'keyword option from [rules.X001]' );

my $indented = join '', map { length $_ > 1 ? "    $_" : $_ } split /^/m, $RULE->slurp_utf8;
ok( index( $readme, $indented ) >= 0, 'README shows t/lib-rules/NoFixme.pm verbatim' );

# The README's sample lib/a.pl and the `puff check` output it shows.
subtest 'README sample output' => sub {
    my ($sample) = $readme =~ /Given this `lib\/a\.pl`:\n\n((?:    .*\n)+)/ or return fail('sample a.pl in README');
    my ($shown)  = $readme =~ /\n    \$ puff check\n((?:    .*\n)+)\nThe points/
        or return fail('sample output in README');
    s/^    //mg for $sample, $shown;

    my $proj = tempdir();
    $proj->child('lib')->mkpath;
    $proj->child( 'lib', 'a.pl' )->spew_utf8($sample);
    $proj->child('.puff.toml')->spew_utf8($config);
    my ( $got, $code ) = puff( $proj, 'check' );
    is( $got, $shown, 'README output matches a real run' );
    is( $code, 1, 'exit 1' );
};

# The corpus harness, as the README shows it, with the rule loaded from
# rule_paths.
run_corpus( 'X001', rule_paths => ['t/lib-rules'] );

done_testing;
