use strict;
use warnings;

my $f = shift;
open(FH, '<', $f) or die; # expect: S003
while (<FH>) { print STDOUT $_ }
close(FH);
