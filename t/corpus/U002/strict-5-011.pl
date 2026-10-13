use 5.011;
my $name = q{x};
my $ref  = \$name;
${$ref} = "!";
print "x\n"; # expect: U002
