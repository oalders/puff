use v5.36;
no strict q{refs};
my $name = 'x';
${"main::$name"} = "x";
print "hello\n"; # expect: U002
