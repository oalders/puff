use v5.10;
my $n = chr 92;
$$n = q{};
print "x\n"; # expect: U002
