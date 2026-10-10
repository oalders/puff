use v5.36;
use Test2::V0;

use Cwd          qw( getcwd );
use Path::Tiny   qw( tempdir );
use Puff::Config ();

my $tmp  = tempdir( CLEANUP => 1, DIR => $ENV{TMPDIR} );
my $orig = getcwd;
chdir $tmp or die;

my $c = Puff::Config->load( path => undef, no_config => 0, cli => {} );
is( $c->select, [qw( S B )], 'default select' );
is( $c->extend_select, [], 'default extend' );
is( $c->ignore, [], 'default ignore' );
is( $c->rule_paths, [], 'default rule_paths' );
is( $c->exclude, [qw( /local /blib /.build /.git )], 'default exclude is anchored' );
is( $c->root, $tmp->realpath->stringify, 'root is the cwd without a config file' );
ok( !$c->unsafe_fixes, 'default unsafe' );
is( $c->rule_options, {}, 'default rule_options' );

$tmp->child('.puff.toml')->spew_utf8(<<'T');
select = ["S00"]
ignore = ["S002"]
unsafe-fixes = true
rule-paths = ["xt/rules"]
exclude = ["t/corpus"]

[rules.S001]
foo = 1
T
$c = Puff::Config->load( path => undef, cli => {} );
is( $c->select, ['S00'], 'select from file (./.puff.toml)' );
is( $c->ignore, ['S002'], 'ignore from file' );
ok( $c->unsafe_fixes, 'unsafe from file' );
is( $c->rule_options, { S001 => { foo => 1 } }, 'rule options' );
is( $c->rule_paths, [ Path::Tiny->cwd->child('xt/rules')->stringify ], 'rule-paths relative to config dir' )
    or diag $c->rule_paths;
is( $c->exclude, [qw( /local /blib /.build /.git t/corpus )], 'exclude adds to defaults' );

$c = Puff::Config->load( path => undef, no_config => 1, cli => {} );
is( $c->select, [qw( S B )], 'no_config ignores file' );

$c = Puff::Config->load(
    path => undef,
    cli  => { select => ['B'], extend_select => ['M'], ignore => ['S001'], unsafe_fixes => 0 },
);
is( $c->select, ['B'], 'cli select replaces' );
is( $c->extend_select, ['M'], 'cli extend appended' );
is( $c->ignore, [ 'S002', 'S001' ], 'cli ignore appended' );
ok( !$c->unsafe_fixes, 'cli unsafe overrides' );

$c = Puff::Config->load( path => undef, cli => { select => undef } );
is( $c->select, ['S00'], 'undef cli value does not override' );

$tmp->child('bad.toml')->spew_utf8(qq{selec = ["S"]\n});
like(
    dies { Puff::Config->load( path => 'bad.toml', cli => {} ) }, qr/Unknown key 'selec'.*bad\.toml/,
    'unknown key dies'
);
like( dies { Puff::Config->load( path => 'missing.toml', cli => {} ) }, qr/not found/, 'missing explicit path dies' );
$tmp->child('broken.toml')->spew_utf8("select = [\n");
like( dies { Puff::Config->load( path => 'broken.toml', cli => {} ) }, qr/Invalid config file/, 'invalid toml dies' );

$tmp->child('strbool.toml')->spew_utf8(qq{unsafe-fixes = "false"\n});
like(
    dies { Puff::Config->load( path => 'strbool.toml', cli => {} ) },
    qr/unsafe-fixes must be true or false/, 'unsafe-fixes string dies'
);
$tmp->child('intbool.toml')->spew_utf8(qq{unsafe-fixes = 1\n});
like(
    dies { Puff::Config->load( path => 'intbool.toml', cli => {} ) },
    qr/unsafe-fixes must be true or false/, 'unsafe-fixes integer dies'
);
$tmp->child('falsebool.toml')->spew_utf8(qq{unsafe-fixes = false\n});
ok( !Puff::Config->load( path => 'falsebool.toml', cli => {} )->unsafe_fixes, 'unsafe-fixes false' );

$tmp->child('sub')->mkpath;
my $abs_rules = $tmp->child('elsewhere')->absolute->stringify;
$tmp->child( 'sub', 'paths.toml' )->spew_utf8(qq{rule-paths = ["rel", "$abs_rules"]\n});
is(
    Puff::Config->load( path => 'sub/paths.toml', cli => {} )->rule_paths,
    [ $tmp->child( 'sub', 'rel' )->absolute->stringify, $abs_rules ],
    'relative rule-paths join the config dir; absolute ones are kept'
);

$tmp->child('.puff.toml')->remove;
$c = Puff::Config->load( path => undef, cli => {} );
is( $c->select, [qw( S B )], 'missing default file gives defaults' );

ok( $c->is_excluded('local/lib/X.pm'), 'default local at the root' );
ok( $c->is_excluded('./local/lib/X.pm'), 'default local at the root, ./ spelling' );
ok( !$c->is_excluded('t/local/http.t'), 'default local not matched below the root' );
ok( !$c->is_excluded('locally/b.pm'), 'segment match is exact' );
ok( !$c->is_excluded( 'lib/X.pm', 'local' ), 'searching local/ itself: its own exclude does not apply' );
ok( !$c->is_excluded( 'X.pm', 'local/lib' ), 'searching below local/: not excluded either' );
ok( !$c->is_excluded( 'lib/X.pm', 't' ), 'searching t/: not under local' );
ok( $c->is_excluded( 'local/x.t', undef ), 'searched dir outside the root: anchored to the searched dir' );
ok( !$c->is_excluded( 't/local/x.t', undef ), 'outside the root: still anchored, not any depth' );
push @{ $c->exclude }, 'vendor', '/t/corpus';
ok( $c->is_excluded('a/vendor/b.pm'), 'user entry without / matches any segment' );
ok( $c->is_excluded( 'vendor/b.pm', undef ), 'user segment entry applies outside the root too' );
ok( $c->is_excluded('t/corpus/x.pl'), 'user /entry anchored at the root' );
ok( !$c->is_excluded('xt/t/corpus/x.pl'), 'user /entry not matched deeper' );
ok( $c->is_excluded( 'corpus/x.pl', 't' ), 'user /entry from a subdirectory search' );
$c = Puff::Config->load( path => undef, cli => {} );
push @{ $c->exclude }, 't/corpus';
ok( $c->is_excluded('t/corpus/x.pl'), 'prefix matches' );
ok( $c->is_excluded('t/corpus'), 'prefix equals path' );
ok( !$c->is_excluded('xt/corpus/x.pl'), 'prefix not mid-segment' );
ok( !$c->is_excluded('t/corpusx/x.pl'), 'prefix at segment boundary' );
ok( !$c->is_excluded('a/t/corpus/x.pl'), 'prefix anchored at start' );

subtest 'non-ASCII exclude entries are UTF-8 bytes' => sub {
    my $proj = $tmp->child('utf8');
    $proj->mkpath;
    $proj->child('.puff.toml')->spew_utf8(qq{exclude = ["caf\x{e9}"]\n});
    my $c = Puff::Config->load( path => $proj->child('.puff.toml')->stringify, cli => {} );
    is( $c->exclude->[-1], "caf\xc3\xa9", 'entry is encoded to UTF-8 bytes' );
    ok( $c->is_excluded("a/caf\xc3\xa9/x.pm"), 'matches a byte-string path' );
};

subtest 'root is the config file directory' => sub {
    my $proj = $tmp->child('proj');
    $proj->child('sub')->mkpath;
    $proj->child('.puff.toml')->spew_utf8('');
    my $c = Puff::Config->load( path => $proj->child('.puff.toml')->stringify, cli => {} );
    is( $c->root, $proj->realpath->stringify, 'root' );
};

chdir $orig;
done_testing;
