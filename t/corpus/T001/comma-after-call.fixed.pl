use strict;
use warnings;
use Test::More;
use List::Util qw( first );

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
my @s = sort { is( $a, $b ), 1 } @x;               # expect: T001
my @g = grep { is( $_, 'a' ), 1 } @x;               # expect: T001
my $d = do { is( $got, $want ), 'in do' };          # expect: T001
my $f = first { is( $_, 'a' ), 1 } @x;              # expect: T001
if ($got) { ok( $got eq $want ), 'in an if block' }
sub named { ok( $got eq $want ), 'in a sub' }
sub pairmap { ok( $got eq $want ), 'sub named like a block function' }
my $r = is( $got, $want ), 'after assignment';      # expect: T001
foo() or is( $got, $want ), 'after or';             # expect: T001
ok( $got eq $want ), 'statement modifier' for @x;
LBL: ok( $got eq $want ), 'labelled';
sub foo { 1 }

done_testing;
