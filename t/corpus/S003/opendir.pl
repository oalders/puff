use strict;
use warnings;

my $d = shift;
opendir(DH, $d); # expect: S003
my @e = readdir(DH);
closedir(DH);
