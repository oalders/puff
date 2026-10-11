my $n;
BEGIN { $n = chr 92; ${$n} = q{} }
use strict;
use feature 'say';
print "x\n"; # expect: U002
