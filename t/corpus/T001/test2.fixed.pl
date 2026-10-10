use Test2::V0;

my ( $got, $want ) = ( 1, 1 );

is( $got, $want, 'eq' );    # expect: T001
isnt( $got, $want );          # expect: T001

done_testing;
