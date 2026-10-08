use strict;
use warnings;

my $f = shift;
open(my $fh, '<', $f) or die; # expect: S003
while (<$fh>) { print STDOUT $_ }
close($fh);
