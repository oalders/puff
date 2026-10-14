use strict;
use feature 'say';
my %h = ( "\\" => \my $x );
${ $h{"\\"} } = "!";
print "hello\n"; # expect: U002
