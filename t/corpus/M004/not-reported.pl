package My::Plain;

use parent -norequire, 'My::Base';

sub BUILD {
    my $self = shift;
    $self->SUPER::BUILD(@_);
}

package My::Child;

use Moose;
extends 'My::Base';

sub BUILD {
    my $self = shift;
    $self->SUPER::other(@_);
    my $cb = sub { $self->next::method };
    $self->SUPER::DEMOLISH(@_);
}

sub init {
    my $self = shift;
    $self->SUPER::BUILD(@_);
    $self->next::method(@_);
}

sub BUILDARGS {
    my $class = shift;
    return $class->SUPER::BUILDARGS(@_);
}

package My::Empty;

use Moose ();

sub BUILD {
    my $self = shift;
    $self->SUPER::BUILD(@_);
}

1;
