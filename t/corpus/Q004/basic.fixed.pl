use strict;
use warnings;

sub foo { return @_ }
sub _bar { return 1 }
package Foo { sub bar { return 2 } }
package main;

my $x = 1;
foo($x); # expect: Q004
my $y = foo( $x, 2 ); # expect: Q004
my @z = ( foo(1), _bar() ); # expect: Q004 Q004
Foo::bar(1); # expect: Q004
::foo(3); # expect: Q004
foo (4); # expect: Q004
my $h = { a => foo(5) }; # expect: Q004
print foo(6), "\n"; # expect: Q004
my $n = $x & foo(7); # expect: Q004
my $m = !foo(8); # expect: Q004
foo(9) if _bar(); # expect: Q004
my @w = map { foo($_) } 1, 2; # expect: Q004
sub wrap { return foo(@_) } # expect: Q004
my $s = "@{[ 1 ]}" . foo(10); # expect: Q004
my $e = foo( [1] )->[0]; # expect: Q004
my $p = foo (1) + 2; # expect: Q004
my @q = foo( _bar(1) ); # expect: Q004 Q004
my @t = foo(1, # expect: Q004
    2);
my $u = 1 + Foo::bar(1); # expect: Q004
my $v = \foo(11); # expect: Q004
my @rr = \(foo(12)); # expect: Q004
my @rv = reverse foo(1, 2); # expect: Q004
my @mp = map foo($_), 1, 2; # expect: Q004
my @gr = grep foo($_), 1, 2; # expect: Q004
my $jn = join foo(','), 1, 2; # expect: Q004
sub wa { return wantarray ? foo(1) : 0 } # expect: Q004
