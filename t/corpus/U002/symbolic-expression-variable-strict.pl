use strict;
use feature 'say';
my ( $c, $x, $y ) = ( 1, \my $p, \my $q );
${ $c ? $x : $y } = "x";
print "hello\n"; # expect: U002
