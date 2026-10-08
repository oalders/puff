use strict;
use warnings;

sub keep_alive {
    my ( $tmp, $dir ) = make_tempdir();    # expect: B006
    my $handle = open_thing();    # expect: B006
    my ( $x, $y ) = ( 1, 2 );    # expect: B006
    my ( @all, $last ) = split / /, shift;    # expect: B006
    return ( $dir, $x, $last );
}
