use v5.36;
no strict q{refs};
my $name = q{x};
${ "main::" . $name } = "x";
say "hello"; # expect: U002
