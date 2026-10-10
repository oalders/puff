use Test2::Tools::Basic;
use Test2::Tools::Compare;

my ( $got, $want ) = ( 1, 1 );

is( $got, $want );    # expect: T001
ok( $got ne $want );

done_testing;
