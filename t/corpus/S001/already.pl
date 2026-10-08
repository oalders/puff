use strict;
use Math::Random::Secure qw(rand);

my $x = rand(10);
srand(1); # expect: S001
