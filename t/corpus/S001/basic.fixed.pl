use strict;
use warnings;
use Crypt::PRNG qw(rand);

print rand(10); # expect: S001
print int(rand 5); # expect: S001
