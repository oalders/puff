use v5.12;
my $name = q{x};
my $ref  = \$name;
${$ref} = "!";
print "x\n"; # expect: U002
