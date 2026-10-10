use v5.36;
no strict q{refs};
my ( $class, $n, %h ) = ( 'main', 1 );
*{"${class}::foo"} = sub {1};
my $v = ${ $h{"k$n"} };
say "hello"; # expect: U002
