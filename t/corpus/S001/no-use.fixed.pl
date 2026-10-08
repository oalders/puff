#!/usr/bin/env perl

my $sides = 6;
use Crypt::PRNG qw(rand);
print rand($sides); # expect: S001
print rand; # expect: S001
