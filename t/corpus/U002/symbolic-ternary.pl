use v5.36;
no strict q{refs};
my $c = 1;
${ $c ? "\\" : "x" } = "x";
print "hello\n"; # expect: U002
