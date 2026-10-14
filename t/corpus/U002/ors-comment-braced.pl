use v5.36;
my $x = "@{[ ${ # a comment
\ } = q{} ]}";
print "x\n"; # expect: U002
