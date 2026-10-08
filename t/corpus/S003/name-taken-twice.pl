use strict;
use warnings;

my ( $f, $log, @log_fh ) = @_;
print "${log}\n";
open LOG, '>>', $f or die; # expect: S003
print LOG "line\n";
close LOG;
