use v5.10;
my ( $y, %h ) = ( "\\", x => q{} );
${ $h{x} . "$y" } = "!";
print "hello\n"; # expect: U002
