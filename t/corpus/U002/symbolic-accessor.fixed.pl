use v5.10;
my $class = q{main};
*{"${class}::foo"} = sub {1};
say "hello"; # expect: U002
