use v5.36;
no strict q{refs};
my %h = ( "\\" => "\\" );
${ $h{"\\"} } = "!";
print "hello\n"; # expect: U002
