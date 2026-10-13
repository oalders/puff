use strict;
use feature 'say';
my %h = ( ORS => \my $x );
${ $h{ORS} } = "!";
print "hello\n"; # expect: U002
