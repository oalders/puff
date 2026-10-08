use strict;
use warnings;

my $f  = shift;
my $in = 1;
open(IN, '<', $f); # expect: S003
my @l = <IN>;
close IN;
