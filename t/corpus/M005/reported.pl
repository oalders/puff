package My::Point;

use strict;
use warnings;
use Moose; # expect: M005

has x => ( is => 'ro' );

__PACKAGE__->meta->make_immutable;

package My::Role;
use Moose::Role; # expect: M005
use Moose::Role;

package My::Moo {
    use Moo; # expect: M005
    has name => ( is => 'ro' );
}

package My::Mouse {
    use Mouse ('has'); # expect: M005
}

package My::Shared;
use Moo; has size => ( is => 'ro' ); # expect: M005

package My::Late;
use namespace::autoclean;

package My::Unmarked;
use Moose; # expect: M005
use MooseX::MarkAsMethods;

package My::Off;
use Moose; # expect: M005
use MooseX::MarkAsMethods autoclean => 0;

package My::Maybe;
use Moose; # expect: M005
use MooseX::MarkAsMethods autoclean => $ENV{CLEAN};

package My::NotAKey;
use Moose; # expect: M005
use MooseX::MarkAsMethods other => 'autoclean', 1 => 1;

package My::Chained;
use Moose; # expect: M005
use MooseX::MarkAsMethods autoclean => 1 => 2;

package main;
use Moose; # expect: M005

1;
