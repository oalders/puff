use strict;
use warnings;

my $s = ''; # expect: Q003
my $t = ""; # expect: Q003
my %h = ( '' => '', x => "" ); # expect: Q003 Q003 Q003
print $h{''}, join( '', 'a', 'b' ), "\n"; # expect: Q003 Q003
$s = '' unless defined $s; # expect: Q003
