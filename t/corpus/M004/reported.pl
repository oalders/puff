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
    $self->SUPER::BUILD($args); # expect: M004
    $self->{child} = 1;
}

sub DEMOLISH {
    my $self = shift;
    $self->SUPER::DEMOLISH(@_); # expect: M004
}

package My::Moo;

use Moo;
extends 'My::Base';

sub BUILD {
    my $self = shift;
    $self->maybe::next::method(@_); # expect: M004
    $self->next::method; # expect: M004
    return;
}

package My::Mouse {
    use Mouse;
    extends 'My::Base';

    sub BUILD {
        my $self = shift;
        if ( $self->{x} ) {
            $self->SUPER::BUILD(@_); # expect: M004
        }
        $self->SUPER::BUILD(@_); $self->{y} = 1; # expect: M004
    }
}

1;
