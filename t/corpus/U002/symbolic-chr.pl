use v5.36;
no strict q{refs};
${ chr(92) } = "!";
print "hello\n"; # expect: U002
