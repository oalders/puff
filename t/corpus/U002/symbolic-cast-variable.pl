use v5.36;
no strict 'refs';
my $n = chr 92;
$$n = q{};
print "x\n"; # expect: U002
