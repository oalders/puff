use v5.36;
no strict q{refs};
${ (qw/\\/)[0] } = "!";
print "hello\n"; # expect: U002
