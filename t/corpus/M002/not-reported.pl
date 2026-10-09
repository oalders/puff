package My::Point;

use Moose;

has x      => ( is => 'ro' );
has y      => ( is => 'bare' );
has '+z'   => ( default => 1 );
has getter => ( reader => 'get_getter' );
has setter => ( writer => 'set_setter' );
has both   => ( accessor => 'both_value' );
has helper => ( handles => [qw( run )] );
has flag   => ( predicate => 'has_flag' );
has opts   => %options;
has more   => ( isa => 'Int', @extra );
has $name  => ( isa => 'Int' );
has lazy_o => ( is => 'lazy' );

sub method {
    has inner => ( isa => 'Int' );
}

package My::Moo;

use Moo;

has name => ( is => 'ro' );
has size => ( is => 'rwp' );
has '+inherited' => ( default => 1 );

package My::Plain;

sub has { }
has thing => ( isa => 'Int' );

package My::Empty;
use Moose ();
has other => ( isa => 'Int' );

1;
