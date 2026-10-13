use strict;
use v5.10;
my $name = q{x};
my $ref  = \$name;
${$ref} = "!";
print "x\n"; # expect: U002
