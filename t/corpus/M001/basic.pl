package My::Point;

use strict;
use warnings;
use Moose; # expect: M001

has x => ( is => 'ro' );
has y => ( is => 'ro' );

1;
