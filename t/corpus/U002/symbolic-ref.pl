use v5.36;
no strict q{refs};
my $name = q{x};
my $ref = \$name;
${$ref} = "!";
print "hello\n"; # expect: U002
