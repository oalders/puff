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
# run of 100k `$` followed by `\$\n` once took seconds).
for my $run ( '$', '\\', '$\\', '\\$' ) {
    my $long  = $run x ( 100_000 / length $run );
    my @tails = ( '\\n', '$\\n', '\\$\\n', '$$\\n', '\\\\n' );
    my $text  = "use v5.36;\n" . join q{}, map {qq{print "$long$_";\n}} @tails;
    my $start = time;
    lines($text);
    ok( time - $start < 2, "a 100k run of '$run' is checked quickly" );
}

my $dollars = '$' x 100_000;
my $escaped = '\\$' x 50_000;
is( lines(qq{use v5.36;\nprint "$dollars\\\$\\n";\n}), [2], 'a long run of $, then \\$\\n, is reported' );
is( lines(qq{use v5.36;\nprint "$escaped\$\\n";\n}), [], 'a long run of \\$, then $\\n, is not' );

done_testing;
