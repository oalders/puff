use strict;
use warnings;
use Test::More;

my ( $got, $want ) = ( 1, 1 );

ok( $got eq $want ), 'name outside the call';
ok ( $got == $want ), 'with a space';
ok( $got eq $want ) => 'fat comma';
ok( $got eq $want, 'name inside' );    # expect: T001

done_testing;
