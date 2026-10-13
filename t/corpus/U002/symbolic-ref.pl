use v5.10;
my $name = q{x};
my $ref = \$name;
${$ref} = "!";
print "hello\n"; # expect: U002
