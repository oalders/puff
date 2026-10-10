use v5.36;
use Test2::V0;

use lib 't/lib';
use TestCommand qw( run_capture );

# Corpus inputs should be real Perl, so a rule is tested on code perl
# accepts. These are our own fixtures, so running perl -c on them is safe.
# t/lib-stub stands in for optional modules the fixtures use. The *.fixed.pl
# files are checked by t/fixed-compiles.t.

use Path::Tiny qw( path );

# Files that do not compile on purpose or that need a module the stubs do
# not provide. Remove an entry when its file is made to compile.
my %SKIP = (
    'A001/not-reported.pl'          => 'uses undeclared @a and %a under strict',
    'B006/not-reported.pl'          => 'fragments using undeclared variables',
    'B009/not-reported.pl'          => 'fragments using undeclared variables',
    'M002/not-reported.pl'          => 'calls has after `use Moose ()`, which imports nothing',
    'M002/reported.pl'              => 'needs Moo::Role',
    'M003/not-reported.pl'          => 'needs Moo::Role',
    'M005/not-reported.pl'          => 'needs namespace::clean',
    'S001/already-paren-qw.pl'      => 'needs Math::Random::Secure',
    'S001/already-paren.pl'         => 'needs Math::Random::Secure',
    'S001/already-quoted.pl'        => 'needs Math::Random::Secure',
    'S001/already.pl'               => 'needs Math::Random::Secure',
    'S003/declined.pl'              => 'bareword filehandles under strict, the rule input',
    'S003/in-sub.pl'                => 'bareword filehandles under strict, the rule input',
    'S003/not-reported.pl'          => 'bareword filehandles under strict, the rule input',
    'S003/print.pl'                 => 'bareword filehandles under strict, the rule input',
    'S019/not-reported.pl'          => 'our with a package-qualified name and undeclared variables',
    'S019/unfixable.pl'             => 'uses undeclared @input',
    'S020/not-reported.pl'          => 'indirect object syntax (new LWP::UserAgent) under v5.36',
    'S020/reported.pl'              => 'indirect object syntax (new LWP::UserAgent) under v5.36',
    'T001/compare-isnt-imported.pl' => 'needs Test2::Tools::Basic',
    'T001/compare-isnt.pl'          => 'needs Test2::Tools::Basic',
    'T001/excluded.pl'              => 'needs Test2::V0',
    'T001/not-reported.pl'          => 'fragments with barewords and bad ok() calls',
    'T001/test2.pl'                 => 'needs Test2::V0',
    'T001/unfixable.pl'             => 'needs Test2::V0',
    'U001/unfixable.pl'             => 'inherits from Tie::StdArray without loading it',
);

my @files = sort grep { /\.pl\z/ && !/\.fixed\.pl\z/ }
    map { $_->stringify } map { $_->children } path( 't', 'corpus' )->children;
ok( scalar @files, 'found corpus inputs' );

my %seen;
for my $file (@files) {
    my $key = $file =~ s{\At/corpus/}{}r;
    $seen{$key} = 1;
    if ( my $why = $SKIP{$key} ) {
        note "skipping $file: $why";
        next;
    }
    my $out = run_capture( undef, $^X, '-It/lib-stub', '-c', $file );
    like( $out, qr/\Q$file\E syntax OK$/m, "$file compiles" ) or diag $out;
}
is( [ sort grep { !$seen{$_} } keys %SKIP ], [], 'every skipped file exists' );

done_testing;
