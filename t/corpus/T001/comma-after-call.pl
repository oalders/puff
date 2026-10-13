use strict;
use warnings;
use Test::More;
use List::Util qw( first );

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
my @s = sort { ok( $a eq $b ), 1 } @x;               # expect: T001
my @g = grep { ok( $_ eq 'a' ), 1 } @x;               # expect: T001
my $d = do { ok( $got eq $want ), 'in do' };          # expect: T001
my $f = first { ok( $_ eq 'a' ), 1 } @x;              # expect: T001
if ($got) { ok( $got eq $want ), 'in an if block' }
sub named { ok( $got eq $want ), 'in a sub' }
sub pairmap { ok( $got eq $want ), 'sub named like a block function' }
my $r = ok( $got eq $want ), 'after assignment';      # expect: T001
foo() or ok( $got eq $want ), 'after or';             # expect: T001
ok( $got eq $want ), 'statement modifier' for @x;
LBL: ok( $got eq $want ), 'labelled';
sub foo { 1 }

done_testing;
