use strict;
use warnings;

my $r = new Foo 1 or die; # expect: B004
my $s = new Foo::Bar $r if $r; # expect: B004
