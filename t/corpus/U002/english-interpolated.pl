use v5.36;
use English;
my $x = "@{[ ${ORS} = q() ]}";
print "x\n"; # expect: U002
