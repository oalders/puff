use v5.36;
my $s = 'a';
$s =~ s/a/$\ = ""/e;
print "x\n"; # expect: U002
