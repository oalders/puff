use strict;
use warnings;
use Test::More;

my ( $got, $want, @list, %h, $obj ) = ( 'a', 'a' );

ok( $got eq $want, 'eq with a name' );    # expect: T001
ok( $got eq $want );                      # expect: T001
ok( $got == 1, 'numbers' );               # expect: T001
ok( $got ne 'b', 'ne' );                  # expect: T001
ok( $got != 2 );                          # expect: T001
ok $got eq $want, 'no parens';            # expect: T001
ok $got eq $want, 'modifier' if $got;     # expect: T001
ok $got eq $want or diag 'low or';        # expect: T001
ok( lc($got) eq $h{key}[0], 'nested' );   # expect: T001
ok( join( ',', 1, 2 ) eq '1,2' );         # expect: T001
ok( length $got == 1 );                   # expect: T001
ok( $got . 'x' eq "${want}x" );           # expect: T001
ok( ref($obj) eq __PACKAGE__ );           # expect: T001
ok( Foo->new->name eq 'x' );              # expect: T001
ok( $got =~ /a/ == 1 );                   # expect: T001
ok( !$got eq '' );                        # expect: T001
ok( $got   eq   $want,'spacing' );        # expect: T001
ok(                                       # expect: T001
    $got eq $want,
    'multi-line',
);

done_testing;
