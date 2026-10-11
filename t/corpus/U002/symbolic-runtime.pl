use v5.36;
no strict q{refs};
my $name = q{\\};
${ "main::" . $name } = "x";
print "hello\n"; # expect: U002
