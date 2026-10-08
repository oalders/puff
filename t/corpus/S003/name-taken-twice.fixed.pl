use strict;
use warnings;

my ( $f, $log, @log_fh ) = @_;
print "${log}\n";
open my $log_fh2, '>>', $f or die; # expect: S003
print {$log_fh2} "line\n";
close $log_fh2;
