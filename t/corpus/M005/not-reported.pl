package My::Point;

use Moose;
use namespace::autoclean;

has x => ( is => 'ro' );

package My::Clean;
use namespace::clean;
use Moo;

package My::Sweep {
    use Mouse;
    use namespace::sweep;
}

package My::No;
use Moose;
has y => ( is => 'ro' );
no Moose;

package My::NoRole;
use Moose::Role;
no Moose::Role;

package My::Plain;
use Moose ();
use parent -norequire, 'My::Point';

package My::Marked;
use Moose;
use MooseX::MarkAsMethods autoclean => 1;
use overload '""' => sub { 'marked' };

package My::MarkedRole;
use Moose::Role;
use MooseX::MarkAsMethods ( 'autoclean', '1' );

package My::Other;
use MooseX::Types;

1;
