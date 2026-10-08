use strict;
use warnings;

my $f = shift;
open(LOG, '>', $f); # expect: S003
print LOG "x\n";
close LOG;

open(Log, '>', $f); # expect: S003
print Log "y\n";
close Log;
