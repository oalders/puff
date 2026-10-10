package My::Child;

use Moose;
extends 'My::Base';

sub BUILD {
    my $self = shift;
    return $self->SUPER::BUILD(@_); # expect: M004
}

sub DEMOLISH {
    my $self = shift;
    my $r = $self->next::method(@_); # expect: M004
    $self->SUPER::DEMOLISH(@_) if $r; # expect: M004
    shift->SUPER::DEMOLISH(@_); # expect: M004
}

1;
