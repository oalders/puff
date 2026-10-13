use strict;
use feature 'say';
my $name = q{x};
my $ref  = \$name;
${$ref} = "!";
no strict 'refs';
print "x\n"; # expect: U002
