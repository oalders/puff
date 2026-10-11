use v5.36;
no strict q{refs};
*{ join "", "main::", "\\" } = \"x";
print "hello\n"; # expect: U002
