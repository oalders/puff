package My::Point;

use strict;
use warnings;
use Moose; # expect: M005
use namespace::autoclean;

has x => ( is => 'ro' );

__PACKAGE__->meta->make_immutable;

package My::Role;
use Moose::Role; # expect: M005
use namespace::autoclean;
use Moose::Role;

package My::Moo {
    use Moo; # expect: M005
    use namespace::autoclean;
    has name => ( is => 'ro' );
}

package My::Mouse {
    use Mouse ('has'); # expect: M005
    use namespace::autoclean;
}

package My::Shared;
use Moo; has size => ( is => 'ro' ); # expect: M005

package My::Late;
use namespace::autoclean;

package main;
use Moose; # expect: M005
use namespace::autoclean;

1;
