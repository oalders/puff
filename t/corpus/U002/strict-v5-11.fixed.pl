use v5.11;
my $name = q{x};
my $ref  = \$name;
${$ref} = "!";
say "x"; # expect: U002
