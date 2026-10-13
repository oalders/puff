use v5.10;
${ (qw/\\/)[0] } = "!";
print "hello\n"; # expect: U002
