srand(42); # expect: S001
my $x = CORE::rand(3); # expect: S001
CORE::srand(7); # expect: S001
