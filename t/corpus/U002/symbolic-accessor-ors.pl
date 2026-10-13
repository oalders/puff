use v5.10;
my $class = q{main};
*{"${class}::O" . "RS"} = \"x";
print "hello\n"; # expect: U002
