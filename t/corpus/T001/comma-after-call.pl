use strict;
use warnings;
use Test::More;

my ( $got, $want, @x ) = ( 1, 1, 'a' );

ok( $got eq $want ), 'name outside the call';
ok ( $got == $want ), 'with a space';
ok( $got eq $want ) => 'fat comma';
ok( $got eq $want, 'name inside' );                   # expect: T001
ok( ( $got eq $want ), 'parenthesized operand' );
ok $got eq $want, 'no parens';                        # expect: T001
my @r = ( ok( $got eq $want ), 'in a list' );         # expect: T001
( ok( $got eq $want ), ok( $got eq $want ) );         # expect: T001 T001
my @m = map { ok( $_ eq 'a' ), 1 } @x;                # expect: T001
sub results { return ok( $got eq $want ), 'list' }    # expect: T001

done_testing;
