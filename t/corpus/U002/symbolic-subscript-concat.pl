use v5.36;
no strict q{refs};
my ( $y, %h ) = ( "\\", x => q{} );
${ $h{x} . "$y" } = "!";
print "hello\n"; # expect: U002
