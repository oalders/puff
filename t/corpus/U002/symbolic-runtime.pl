use v5.10;
my $name = q{\\};
${ "main::" . $name } = "x";
print "hello\n"; # expect: U002
