use Test::Most import => [qw( ok is )];

is( $got, $want );    # expect: T001
ok( $got ne $want );
