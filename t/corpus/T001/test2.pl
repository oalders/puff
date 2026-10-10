use Test2::V0;

my ( $got, $want ) = ( 1, 1 );

ok( $got eq $want, 'eq' );    # expect: T001
ok( $got != $want );          # expect: T001

done_testing;
