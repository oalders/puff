use Test::More tests => 2, import => [qw( ok isnt )];

my ( $got, $want ) = ( 1, 1 );

ok( $got eq $want );
ok( $got ne $want );    # expect: T001
