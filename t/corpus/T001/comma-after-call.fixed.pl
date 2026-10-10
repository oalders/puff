use strict;
use warnings;
use Test::More;

my ( $got, $want, @x ) = ( 1, 1, 'a' );

ok( $got eq $want ), 'name outside the call';
ok ( $got == $want ), 'with a space';
ok( $got eq $want ) => 'fat comma';
is( $got, $want, 'name inside' );                   # expect: T001
ok( ( $got eq $want ), 'parenthesized operand' );
is $got, $want, 'no parens';                        # expect: T001
my @r = ( is( $got, $want ), 'in a list' );         # expect: T001
( is( $got, $want ), is( $got, $want ) );         # expect: T001 T001
my @m = map { is( $_, 'a' ), 1 } @x;                # expect: T001
sub results { return is( $got, $want ), 'list' }    # expect: T001

done_testing;
