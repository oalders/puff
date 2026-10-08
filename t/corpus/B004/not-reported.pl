use strict;
use warnings;
use Carp qw( croak );
use Test::More;

package Foo { sub new { return bless {}, shift } sub name { 'foo' } }
package Foo::Bar { sub new { return bless {}, shift } }
package main;

use constant ERROR => 'boom';
my $class = 'Foo';
my $o = Foo->new;
my $p = Foo::Bar->new(1);
my $q = $class->new;
my $r = Foo::->new;
print STDERR "x\n";
print Foo->name, "\n";
my @s = sort Foo::Bar::cmp( 1, 2 ) if 0;
my $h = { new => Foo->new };
isa_ok( Foo->new, 'Foo' );
can_ok Foo => 'new';
ok defined Foo::Bar->new;
croak ERROR if 0;
croak $class if 0;
is ref Foo->new, 'Foo';
my %x = ( Foo => 1 );
sub make { return Foo::Bar->new }
my $f = make Foo::Bar::helper(1) if 0;
done_testing;
