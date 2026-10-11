use strict qw(refs);
use feature 'say';
my $name = q{x};
my $ref  = \$name;
${$ref} = "!";
print "x\n"; # expect: U002
