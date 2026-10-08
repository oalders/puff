package Foo;
use strict;
use Crypt::PRNG qw(rand);
sub roll { rand(6) } # expect: S001
1;
