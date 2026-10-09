use Test::More;

my ( $got, $want ) = ( 1, 1 );

ok( $got eq $want );

sub ok { return Test::More::ok(@_) }

done_testing;
