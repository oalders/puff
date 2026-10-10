my ( $got, $want ) = ( 1, 1 );

ok( $got eq $want );

use Test::More;
is( $got, $want );    # expect: T001

done_testing;
