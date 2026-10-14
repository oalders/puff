use strict;
use feature 'say';
my $n = \my $x;
$$n = q{};
say "x"; # expect: U002
