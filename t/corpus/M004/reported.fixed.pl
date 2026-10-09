package My::Base;

use Moose;

sub BUILD {
    my $self = shift;
    $self->{ready} = 1;
}

package My::Child;

use Moose;
extends 'My::Base';

sub BUILD {
    my ( $self, $args ) = @_;
    $self->{child} = 1;
}

sub DEMOLISH {
    my $self = shift;
}

package My::Moo;

use Moo;
extends 'My::Base';

sub BUILD {
    my $self = shift;
    return;
}

package My::Mouse {
    use Mouse;
    extends 'My::Base';

    sub BUILD {
        my $self = shift;
        if ( $self->{x} ) {
        }
        $self->{y} = 1; # expect: M004
    }
}

1;
