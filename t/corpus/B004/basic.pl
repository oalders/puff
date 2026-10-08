use strict;
use warnings;

my $class = 'Foo::Bar';
my $o = new Foo::Bar(1); # expect: B004
my $p = new Foo; # expect: B004
my $q = new $class( a => 1 ); # expect: B004
my $r = new $class; # expect: B004
my $s = create My::Thing(); # expect: B004
my $t = new Foo::Bar:: ; # expect: B004
my @all = ( new Foo, new Foo::Bar(2) ); # expect: B004 B004
my $u = new Foo or die; # expect: B004
my $v = new Foo(1)->name; # expect: B004
return new Foo::Bar if 0; # expect: B004
my $w = new Foo 1, 2; # expect: B004
my $x = new Foo::Bar $r; # expect: B004
my @y = ( new Foo $r || 1, 2 ); # expect: B004
my $z = new Foo -1; # expect: B004
my $last = new Foo ? 1 : 2; # expect: B004
