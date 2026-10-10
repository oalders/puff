use v5.36;
no strict q{refs};
my $class = q{main};
*{"${class}::ORS"} = \"x";
print "hello\n"; # expect: U002
