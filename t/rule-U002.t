use v5.36;
use Test2::V0;

use Time::HiRes qw( time );

use Puff::Engine ();
use Puff::Rules  ();
use Puff::Source ();
use Puff::Test   qw( run_corpus );

run_corpus('U002');

my ($class) = grep { $_->code eq 'U002' } Puff::Rules->load;

sub lines ($text) {
    my $result = Puff::Engine->new( rules => [ $class->new ] )
        ->process_source( Puff::Source->from_string($text), file => 'x.pl' );
    return [ map { $_->line } @{ $result->{violations} } ];
}

# Long runs of `$` and `\` before the `\n` are checked in linear time (a
# run of 100k `$` followed by `\$\n` once took seconds). The tails are on
# lines 2 to 6. Only an even run of backslashes before the `\n` is reported.
# Each takes at most 20 times as long as a run of plain letters of the
# same length (a quadratic check takes hundreds of times as long).
sub timed ($run) {
    my $long  = $run x ( 100_000 / length $run );
    my @tails = ( '\\n', '$\\n', '\\$\\n', '$$\\n', '\\\\n' );
    my $start = time;
    my $lines = lines( "use v5.36;\n" . join q{}, map {qq{print "$long$_";\n}} @tails );
    return ( $lines, time - $start );
}
my ( undef, $plain ) = timed('a');
my %reported = (
    '$'   => [],
    '\\'  => [2],
    '$\\' => [],
    '\\$' => [],
    'a\\' => [6],
);
for my $run ( sort keys %reported ) {
    my ( $lines, $took ) = timed($run);
    is( $lines, $reported{$run}, "a 100k run of '$run' is reported on the right lines" );
    ok( $took < 20 * $plain, "a 100k run of '$run' is checked in linear time" )
        or diag "took ${took}s, plain letters ${plain}s";
}

my $dollars = '$' x 100_000;
my $escaped = '\\$' x 50_000;
is( lines(qq{use v5.36;\nprint "${dollars}a\$\$\\n";\n}), [2], 'a long run of $, then a$$\\n, is reported' );
is( lines(qq{use v5.36;\nprint "$escaped\$\\n";\n}), [], 'a long run of \\$, then $\\n, is not' );

done_testing;
