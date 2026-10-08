use v5.36;
use Test2::V0;

# Every *.fixed.pl in the corpus is fixer output we vouch for, so it must
# compile. These are our own fixtures, so running perl -c on them is safe.
# t/lib-stub stands in for optional modules the fixtures use.

use Path::Tiny qw( path );

my %SKIP = (
    # 'S00N/name.fixed.pl' => 'reason',
);

my @files = sort grep {/\.fixed\.pl\z/} map { $_->stringify } map { $_->children } path( 't', 'corpus' )->children;
ok( scalar @files, 'found fixed fixtures' );

for my $file (@files) {
    my $key = $file =~ s{\At/corpus/}{}r;
    if ( my $why = $SKIP{$key} ) {
        note "skipping $file: $why";
        next;
    }
    my $out = qx{\Q$^X\E -It/lib-stub -c \Q$file\E 2>&1};
    like( $out, qr/\Q$file\E syntax OK$/m, "$file compiles" ) or diag $out;
}

done_testing;
