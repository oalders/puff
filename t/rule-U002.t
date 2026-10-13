use v5.36;
use Test2::V0;

use Time::HiRes qw( time );

use PPI          ();
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

# Each form the raw-text scan looks for withholds the fix on its own, even
# in a comment, which PPI does not look into.
sub fixable ($text) {
    my $result = Puff::Engine->new( rules => [ $class->new ] )
        ->process_source( Puff::Source->from_string($text), file => 'x.pl' );
    return [ map { $_->fixable } @{ $result->{violations} } ];
}
is( fixable(qq{use v5.36;\n# nothing\nprint "x\\n";\n}), [1], 'a plain comment keeps the fix' );
for my $raw (
    '$\\', '$ \\', "\$\t\\", '${\\}', '${ \\ }', '$::ORS', 'ORS', 'OUTPUT_RECORD_SEPARATOR',
    'output_record_separator', 'no strict'
) {
    is( fixable(qq{use v5.36;\n# $raw\nprint "x\\n";\n}), [0], "'$raw' in a comment withholds the fix" );
}
is( fixable(qq{use v5.36;\n# CORS, ORS_X\nprint "x\\n";\n}), [1], 'ORS inside a longer word does not' );

# The whole document is searched once, not once per print: a file with
# 3000 prints took minutes. Whole-document searches are counted, as
# timings would be flaky.
{
    no warnings 'redefine';
    my %calls;
    my %orig = ( find => PPI::Node->can('find'), serialize => PPI::Document->can('serialize') );
    local *PPI::Node::find          = sub { $calls{find}++;      goto &{ $orig{find} } };
    local *PPI::Document::serialize = sub { $calls{serialize}++; goto &{ $orig{serialize} } };
    my $n    = 200;
    my $text = "use v5.36;\n" . qq{print "x\\n";\n} x $n;
    my $doc  = PPI::Document->new( \$text );
    $doc->index_locations;
    my @prints = grep { $_->content eq 'print' } @{ $doc->find('PPI::Token::Word') };
    %calls = ();
    my $rule  = $class->new;
    my @found = map { $rule->check( $_, $doc ) } @prints;
    is( scalar @found, $n, 'every print is reported' );
    cmp_ok( $calls{find}      // 0, '<', 10, 'finds: once per document, not per print' );
    cmp_ok( $calls{serialize} // 0, '<', 3, 'serializes: once per document, not per print' );
}

done_testing;
