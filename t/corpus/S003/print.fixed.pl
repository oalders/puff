use strict;
use warnings;

my $f = shift;
open(my $out, '>', $f); # expect: S003
print {$out} "x\n";
printf {$out} "%s", 1;
print {$out} "y";
close $out;
