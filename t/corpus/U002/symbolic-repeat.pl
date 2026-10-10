use v5.36;
no strict q{refs};
${ "\\" x 1 } = "x";
print "hello\n"; # expect: U002
