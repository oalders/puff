use strict;
use warnings;

my $f  = shift;
my $in = 1;
open(my $in_fh, '<', $f); # expect: S003
my @l = <$in_fh>;
close $in_fh;
