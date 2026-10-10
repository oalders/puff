use Test2::Tools::Basic;
use Test2::Tools::Compare qw( is isnt );

my ( $got, $want ) = ( 1, 1 );

ok( $got eq $want );    # expect: T001
ok( $got ne $want );    # expect: T001

done_testing;
