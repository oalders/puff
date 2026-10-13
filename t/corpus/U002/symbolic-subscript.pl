use v5.10;
my ( $n, %h ) = ( 1, k1 => q{x} );
my $v = ${ $h{"k$n"} };
print "hello\n"; # expect: U002
