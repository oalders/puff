use v5.36;
use Test2::V0;

# Checks the example rule in the README ("Writing a rule"). The README shows
# t/lib-rules/NoFixme.pm verbatim, so this test keeps the example working.

use Cwd        qw( getcwd );
use Path::Tiny qw( path tempdir );

my $root  = path(getcwd)->absolute;
my @PERL  = ( $^X, '-I' . $root->child('lib'), '-I' . $root->child( 'local', 'lib', 'perl5' ) );
my $PUFF  = $root->child( 'bin', 'puff' )->stringify;
my $RULE  = $root->child( 't', 'lib-rules', 'NoFixme.pm' );

sub puff ( $dir, @args ) {
    my $cmd  = join ' ', map { quotemeta } @PERL, $PUFF, @args;
    my $orig = getcwd;
    chdir $dir or die "chdir $dir: $!";
    my $out  = qx{$cmd 2>&1};
    my $exit = $? >> 8;
    chdir $orig or die "chdir $orig: $!";
    return ( $out, $exit );
}

# rule-paths is relative to the config file, so the rule is copied next to it.
my $dir = tempdir();
$dir->child('rules')->mkpath;
$RULE->copy( $dir->child( 'rules', 'NoFixme.pm' ) );
my $config = qq{rule-paths = ["rules"]\nextend-select = ["X"]\n};
$dir->child('.puff.toml')->spew_utf8($config);
$dir->child('a.pl')->spew_utf8("# FIXME: tidy\nmy \$x = 1;    # FIXME later\n");

my ( $out, $exit ) = puff( $dir, 'check', 'a.pl' );
is( $exit, 1, 'violations found' );
like( $out, qr{^a\.pl:1:1: X001 Use TODO instead of FIXME \[\*\]$}m,  'first comment reported' );
like( $out, qr{^a\.pl:2:15: X001 Use TODO instead of FIXME \[\*\]$}m, 'second comment reported' );

( $out, $exit ) = puff( $dir, 'rule', 'X001' );
is( $exit, 0, 'rule X001 explained' );
like( $out, qr{^X001: Use TODO instead of FIXME\nFix safety: safe\n}, 'rule header' );

( $out, $exit ) = puff( $dir, 'check', '--fix', 'a.pl' );
is( $exit, 0, 'clean after the safe fix' );
is( $dir->child('a.pl')->slurp_utf8, "# TODO: tidy\nmy \$x = 1;    # TODO later\n", 'comments rewritten' );

$dir->child('b.pl')->spew_utf8("# NOTE: x\n# KEEP this\n");
$dir->child('.puff.toml')->spew_utf8( $config . qq{[rules.X001]\nkeyword = "KEEP"\n} );
( $out, $exit ) = puff( $dir, 'check', 'b.pl' );
like( $out, qr{^b\.pl:2:1: X001 Use TODO instead of KEEP}m, 'keyword option from [rules.X001]' );

my $indented = join '', map { length $_ > 1 ? "    $_" : $_ } split /^/m, $RULE->slurp_utf8;
ok( index( $root->child('README.md')->slurp_utf8, $indented ) >= 0, 'README shows t/lib-rules/NoFixme.pm verbatim' );

done_testing;
