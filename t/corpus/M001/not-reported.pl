package My::Thing;

use strict;
use warnings;
use Moose;
use Moose ();
use Moose::Role ();

has x => ( is => 'ro' );

my $meta = __PACKAGE__->meta;
$meta->make_immutable;

package My::Plain;
use Moose ();

package My::Role;
use Moose::Role;
requires 'x';

1;
