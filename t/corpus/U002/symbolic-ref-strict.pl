use v5.36;
my $name = q{x};
my $ref = \$name;
${$ref} = "!";
$$ref = "!";
print "hello\n"; # expect: U002
