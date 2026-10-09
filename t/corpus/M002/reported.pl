package My::Point;

use Moose;

has x => ( isa => 'Int' ); # expect: M002
has 'y' => ( isa => 'Int', default => 0 ); # expect: M002
has [qw(width height)] => ( isa => 'Int' ); # expect: M002
has( 'z', isa => 'Int' ); # expect: M002
has depth => isa => 'Int'; # expect: M002
has label => ( is => 'ro' );

__PACKAGE__->meta->make_immutable;

package My::Moo;

use Moo;

has name => ( is => 'ro' );
has size => ( reader => 'get_size' ); # expect: M002
has ['a', 'b'] => ( default => 1 ); # expect: M002

package My::Role {
    use Moose::Role;
    has colour => ( isa => 'Str' ); # expect: M002
}

package My::MooRole {
    use Moo::Role;
    has shade => ( required => 1 ); # expect: M002
}

package My::Mouse;
use Mouse;
has weight => ( isa => 'Int' ); # expect: M002

1;
