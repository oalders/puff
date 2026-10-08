use v5.36;
use List::Util qw( reduce pairmap );

my @x = (3, 1, 2);
my %h = ( a => 1 );
my @s = sort { $a <=> $b } @x;
my @r = reverse sort { $h{$a} <=> $h{$b} } @x;
my @l = sort { lc($a) cmp lc($b) or do { $b <=> $a } } @x;
my $sum = reduce { $a + $b } @x;
my $max = List::Util::reduce { $a > $b ? $a : $b } @x;
my @p = pairmap { ( $a, $b ) } @x;
my @n = sort by_num @x;
my @m = sort( by_len @x );
sub by_num { $a <=> $b }
sub by_len { length($a) <=> length($b) }
my @z = ( $a[0], $a{x}, $main::a, $::b, @a );
print "$a and $b in a string";
