use v5.36;
my $s = q{a};
$s =~ s/a/${\} = ''/e;
print "x\n"; # expect: U002
