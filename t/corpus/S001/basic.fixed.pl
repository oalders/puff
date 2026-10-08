use strict;
use warnings;
use Math::Random::Secure qw(rand);

my $x = rand(10); # expect: S001
print int(rand 5); # expect: S001
