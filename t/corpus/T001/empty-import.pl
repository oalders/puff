use Test::More ();

my ( $got, $want ) = ( 1, 1 );

Test::More::ok( $got eq $want );
ok( $got eq $want );

Test::More::done_testing();
