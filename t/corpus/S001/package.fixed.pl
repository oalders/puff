package Foo;
use strict;
use Math::Random::Secure qw(rand);
sub roll { rand(6) } # expect: S001
1;
