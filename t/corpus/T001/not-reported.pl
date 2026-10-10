use strict;
use warnings;
use Test::More;

my ( $got, $want, $other, $tb ) = ( 1, 1 );

ok( $got == $want && $other );
ok( $got == $want || $other );
ok( $got == $want // $other );
ok( $got eq $want or $other );
ok( $got eq $want and $other );
ok( not $got eq $want );
ok( $got eq $want ? 1 : 0 );
ok( $got == $want == $other );
ok( $got <=> $want );
ok( $got cmp $want );
ok( $got lt $want );
ok( !( $got eq $want ) );
ok( ( $got eq $want ) );
ok( ( 1, 2 ) == 2 );    # PPI does not parse a first argument that starts with parens
ok( $got = $want eq 'a' );
ok( $got & $want == 1 );
ok( $got, $want eq 'a' );
ok( somefunc $got eq $want );
ok( $got eq CONSTANT );
ok( do { $got } eq $want );
ok( $got eq sub {1} );
ok $got eq $want ? 1 : 0;
ok $got eq $want || $other;
ok( $got );
ok();
$tb->ok( $got eq $want );
Test::More::ok( $got eq $want );
my %h = ( ok => 1 );
is( $got, $want );

done_testing;
