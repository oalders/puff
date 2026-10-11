use v5.36;
my $name = q{x};
my $ref = \$name;
${$ref} = "!";
$$ref = "!";
say "hello"; # expect: U002
