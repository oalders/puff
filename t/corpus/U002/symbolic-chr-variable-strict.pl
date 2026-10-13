use strict;
use feature 'say';
my $n = \my $x;
${$n} = q{};
print "x\n"; # expect: U002
