use strict;
use warnings;

my $s = q{}; # expect: Q003
my $t = q{}; # expect: Q003
my %h = ( q{} => q{}, x => q{} ); # expect: Q003 Q003 Q003
print $h{q{}}, join( q{}, 'a', 'b' ), "\n"; # expect: Q003 Q003
$s = q{} unless defined $s; # expect: Q003
