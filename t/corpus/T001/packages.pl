package Helper;

sub check { return ok( $_[0] eq 'x' ) }

package main;

use Test::More;

my ( $got, $want ) = ( 1, 1 );

ok( $got eq $want );    # expect: T001

package Other {
    ok( $got eq $want );
}

{
    package Inner;
    ok( $got eq $want );
}

ok( $got ne $want );    # expect: T001

done_testing;
