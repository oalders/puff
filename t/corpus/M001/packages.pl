use strict;
use warnings;

package My::Done;
use Moose;
has x => ( is => 'ro' );
__PACKAGE__->meta->make_immutable;

package My::Shape;
use Moose; # expect: M001
has sides => ( is => 'ro' );

package My::Square;
use Moose; # expect: M001
extends 'My::Shape';

1;
