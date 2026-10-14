use v5.36;
eval <<'CODE';
no # a comment
strict;
${ chr 92 } = q{!};
CODE
print "x\n"; # expect: U002
