use v5.36;

# Different sigils are different variables.
my $x  = 1;
my @x  = ($x);
my %x  = ( a => $x[0] );
my $el = $x{a};

# local is not a declaration.
our $level = 0;
local $level = 1;
local $level = 2;

# Sibling blocks and subs may reuse a name.
sub one { my $tmp = 1; return $tmp }
sub two { my $tmp = 2; return $tmp }
{ my $block = 1 }
{ my $block = 2 }
for my $item ( 1, 2 ) { print $item }
for my $item ( 3, 4 ) { print $item }
while ( my $line = shift ) { print $line }
while ( my $line = shift ) { print $line }

# A prototype declares nothing.
sub proto ($$) { my $x = shift; return $x }

# Defaults in a signature may use other variables; only parameters count.
sub defaults ( $self, $opt = [ $x, $el ] ) { my $el = 1; return $el }

# our in different packages names different globals.
package Foo;
our $VERSION = '1.0';

package Bar;
our $VERSION = '1.0';

package Baz {
    our $VERSION = '2.0';
}

# Inner scopes are B008's business, not this rule's.
my $outer = 1;
{ my $outer = 2 }

# A method named state or my is not a declaration.
my $obj = bless {}, 'Foo';
$obj->state($x);
$obj->state($x);

# String evals are not parsed.
eval 'my $x = 1; my $x = 2;';
