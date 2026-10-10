my ( $got, $want ) = ( 1, 1 );

ok( $got eq $want );

use Test::More;
ok( $got eq $want );    # expect: T001

done_testing;
