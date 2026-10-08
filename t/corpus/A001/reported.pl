use v5.36;

my $a = 1; # expect: A001
my ( $x, $b ) = ( 1, 2 ); # expect: A001
print $a + $b; # expect: A001 A001
my @s = sort { $x <=> $x } (3, 1);
if ($x) { print $a } # expect: A001
my @m = map { $a } @s; # expect: A001
my $cmp = sub { $a <=> $b }; # expect: A001 A001
sub helper { return $b } # expect: A001
my @r = sort(sub { $a <=> $b }, 1); # expect: A001 A001
