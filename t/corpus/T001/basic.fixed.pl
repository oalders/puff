use strict;
use warnings;
use Test::More;

my ( $got, $want, @list, %h, $obj ) = ( 'a', 'a' );

is( $got, $want, 'eq with a name' );    # expect: T001
is( $got, $want );                      # expect: T001
is( $got, 1, 'numbers' );               # expect: T001
isnt( $got, 'b', 'ne' );                  # expect: T001
isnt( $got, 2 );                          # expect: T001
is $got, $want, 'no parens';            # expect: T001
is $got, $want, 'modifier' if $got;     # expect: T001
is $got, $want or diag 'low or';        # expect: T001
is( lc($got), $h{key}[0], 'nested' );   # expect: T001
is( join( ',', 1, 2 ), '1,2' );         # expect: T001
is( length $got, 1 );                   # expect: T001
is( $got . 'x', "${want}x" );           # expect: T001
is( ref($obj), __PACKAGE__ );           # expect: T001
is( Foo->new->name, 'x' );              # expect: T001
is( $got =~ /a/, 1 );                   # expect: T001
is( !$got, '' );                        # expect: T001
is( $got, $want,'spacing' );        # expect: T001
is(                                       # expect: T001
    $got, $want,
    'multi-line',
);

done_testing;
