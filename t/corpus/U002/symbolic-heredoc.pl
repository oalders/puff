use v5.36;
no strict q{refs};
${ substr <<E, 0, 1 } = "!";
\\
E
print "hello\n"; # expect: U002
