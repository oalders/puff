use v5.10;
my $name = 'x';
${"main::$name"} = "x";
print "hello\n"; # expect: U002
