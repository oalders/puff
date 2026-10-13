use v5.10;
my $c = 1;
${ $c ? "\\" : "x" } = "x";
print "hello\n"; # expect: U002
