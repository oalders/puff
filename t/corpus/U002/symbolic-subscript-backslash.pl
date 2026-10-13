use v5.10;
my %h = ( "\\" => "\\" );
${ $h{"\\"} } = "!";
print "hello\n"; # expect: U002
