use strict 'refs';
use feature 'say';
my $name = q{x};
my $ref  = \$name;
${$ref} = "!";
say "x"; # expect: U002
