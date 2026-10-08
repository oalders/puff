sub pairfoo (&@) { }
pairfoo { $a + $b } 1, 2; # expect: A001 A001
