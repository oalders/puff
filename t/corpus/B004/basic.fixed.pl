use strict;
use warnings;

my $class = 'Foo::Bar';
my $o = Foo::Bar->new(1); # expect: B004
my $p = Foo->new; # expect: B004
my $q = $class->new( a => 1 ); # expect: B004
my $r = $class->new; # expect: B004
my $s = My::Thing->create(); # expect: B004
my $t = Foo::Bar::->new ; # expect: B004
my @all = ( Foo->new, Foo::Bar->new(2) ); # expect: B004 B004
my $u = Foo->new or die; # expect: B004
my $v = Foo->new(1)->name; # expect: B004
return Foo::Bar->new if 0; # expect: B004
my $w = Foo->new(1, 2); # expect: B004
my $x = Foo::Bar->new($r); # expect: B004
my @y = ( Foo->new($r || 1, 2) ); # expect: B004
my $z = Foo->new(-1); # expect: B004
my $last = Foo->new ? 1 : 2; # expect: B004
