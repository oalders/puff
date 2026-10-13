use v5.10;
*{ join "", "main::", "\\" } = \"x";
print "hello\n"; # expect: U002
