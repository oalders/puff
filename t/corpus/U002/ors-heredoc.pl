use v5.36;
my $x = <<"END";
@{[ $\ = '' ]}
END
print "x\n"; # expect: U002
