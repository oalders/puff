use v5.36;
my $x = "@{[ do { no strict 'refs'; ${ chr 92 } = '' } ]}";
print "x\n"; # expect: U002
