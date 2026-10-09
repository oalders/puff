use Test2::Tools::Basic;
use Test2::Tools::Compare qw( is isnt );

my ( $got, $want ) = ( 1, 1 );

is( $got, $want );    # expect: T001
isnt( $got, $want );    # expect: T001

done_testing;
