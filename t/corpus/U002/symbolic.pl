use v5.36;
no strict q{refs};
${"\\"} = "x";
print "hello\n"; # expect: U002
