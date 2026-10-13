use v5.10;
${ substr <<E, 0, 1 } = "!";
\\
E
print "hello\n"; # expect: U002
