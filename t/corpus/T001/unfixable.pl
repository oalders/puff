use strict;
use warnings;
use Test2::V0;

my ( $got, @list, %h, $ref ) = (1);

ok( @list == 2, 'array' );                   # expect: T001
ok( %h == 0 );                               # expect: T001
ok( $ref->@* == 1 );                         # expect: T001
ok( @{$ref} == 1 );                          # expect: T001
ok( $got eq 'a', 'name', 'diag' );           # expect: T001
ok( $got eq    # expect: T001
    'a' );

done_testing;
