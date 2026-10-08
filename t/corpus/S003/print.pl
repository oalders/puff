use strict;
use warnings;

my $f = shift;
open(OUT, '>', $f); # expect: S003
print OUT "x\n";
printf OUT "%s", 1;
print {OUT} "y";
close OUT;
