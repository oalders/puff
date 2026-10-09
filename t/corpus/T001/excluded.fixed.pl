use Test2::V0 -no_srand => 1, qw( !is );

my ( $got, $want ) = ( 1, 1 );

ok( $got eq $want );
isnt( $got, $want );    # expect: T001

done_testing;
