use v5.36;
no strict q{refs};
my ( $c, $x ) = ( 1, q{\\} );
${ $c ? "$x" : "y" } = "x";
print "hello\n"; # expect: U002
