use v5.10;
my ( $c, $x ) = ( 1, q{\\} );
${ $c ? "$x" : "y" } = "x";
print "hello\n"; # expect: U002
