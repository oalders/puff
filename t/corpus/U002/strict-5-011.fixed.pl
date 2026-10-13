use 5.011;
my $name = q{x};
my $ref  = \$name;
${$ref} = "!";
say "x"; # expect: U002
