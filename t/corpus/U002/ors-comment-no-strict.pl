use v5.36;
my $x = "@{[ do { no # a comment
 strict; ${ chr 92 } = q{} } ]}";
print "x\n"; # expect: U002
