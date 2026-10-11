use v5.36;
no strict q{refs};
my $class = q{main};
*{"${class}::foo"} = sub {1};
say "hello"; # expect: U002
