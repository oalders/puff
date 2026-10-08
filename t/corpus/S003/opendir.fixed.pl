use strict;
use warnings;

my $d = shift;
opendir(my $dh, $d); # expect: S003
my @e = readdir($dh);
closedir($dh);
