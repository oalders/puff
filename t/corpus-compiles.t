use v5.36;
use Test2::V0;

use lib 't/lib';
use TestCommand qw( run_capture );

# Corpus inputs should be real Perl, so a rule is tested on code perl
# accepts. perl -c runs BEGIN blocks and `use` at compile time, so this test
# runs code from every corpus file: review corpus files as code. t/lib-stub
# stands in for optional modules the fixtures use. The *.fixed.pl files are
# checked by t/fixed-compiles.t.

use Config     qw( %Config );
use FindBin    qw( $Bin );
use Path::Tiny qw( path );

my $STUBS = path( $Bin, 'lib-stub' )->absolute;

# perl -c sees the modules this test sees, however they were found (-I,
# PERL5LIB or prove), so the result does not depend on how it is run.
local $ENV{PERL5LIB} = join $Config{path_sep}, map { path($_)->absolute } grep { !ref } @INC;

# Files that do not compile on purpose or that need a module the stubs do
# not provide. Each must still fail perl -c, so an entry is removed when its
# file is made to compile.
my %SKIP = (
    'A001/not-reported.pl'     => 'uses undeclared @a and %a under strict',
    'B006/not-reported.pl'     => 'fragments using undeclared variables',
    'B009/not-reported.pl'     => 'fragments using undeclared variables',
    'M002/not-reported.pl'     => 'calls has after `use Moose ()`, which imports nothing',
    'M002/reported.pl'         => 'needs Moo::Role',
    'M003/not-reported.pl'     => 'needs Moo::Role',
    'M003/reported.pl'         => 'needs Class::MOP: Moo is loaded after Moose',
    'M005/not-reported.pl'     => 'needs namespace::clean',
    'S001/already-paren-qw.pl' => 'needs Math::Random::Secure',
    'S001/already-paren.pl'    => 'needs Math::Random::Secure',
    'S001/already-quoted.pl'   => 'needs Math::Random::Secure',
    'S001/already.pl'          => 'needs Math::Random::Secure',
    'S003/declined.pl'         => 'bareword filehandles under strict, the rule input',
    'S003/in-sub.pl'           => 'bareword filehandles under strict, the rule input',
    'S003/not-reported.pl'     => 'bareword filehandles under strict, the rule input',
    'S003/print.pl'            => 'bareword filehandles under strict, the rule input',
    'S019/not-reported.pl'     => 'our with a package-qualified name and undeclared variables',
    'S019/unfixable.pl'        => 'uses undeclared @input',
    'S020/not-reported.pl'     => 'indirect object syntax (new LWP::UserAgent) under v5.36',
    'S020/reported.pl'         => 'indirect object syntax (new LWP::UserAgent) under v5.36',
    'T001/not-reported.pl'     => 'fragments with barewords and bad ok() calls',
    'U001/unfixable.pl'        => 'inherits from Tie::StdArray without loading it',
);

my @files = sort grep { /\.pl\z/ && !/\.fixed\.pl\z/ }
    map { $_->stringify } map { $_->children } path( 't', 'corpus' )->children;
ok( scalar @files, 'found corpus inputs' );

my %seen;
for my $file (@files) {
    my $key = $file =~ s{\At/corpus/}{}r;
    $seen{$key} = 1;
    my $out = run_capture( undef, $^X, "-I$STUBS", '-c', $file );
    if ( my $why = $SKIP{$key} ) {
        unlike( $out, qr/\Q$file\E syntax OK$/m, "$file does not compile: $why" );
        next;
    }
    like( $out, qr/\Q$file\E syntax OK$/m, "$file compiles" ) or diag $out;
}
is( [ sort grep { !$seen{$_} } keys %SKIP ], [], 'every skipped file exists' );

done_testing;
