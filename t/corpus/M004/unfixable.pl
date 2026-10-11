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

package My::Blocks;

use Moo;
extends 'My::Base';

# Removing the only statement would leave `map { } @parts`, which does not
# compile, or change the value of the block.
sub BUILD {
    my ( $self, @parts ) = @_;
    my @a = map { $self->SUPER::BUILD($_); } @parts; # expect: M004
    my @b = grep { $self->next::method($_) } @parts; # expect: M004
    my @c = sort { $self->maybe::next::method(@_); } @parts; # expect: M004
    my $d = do { $self->SUPER::BUILD(@_); }; # expect: M004
    eval { $self->SUPER::BUILD(@_); }; # expect: M004
}

1;
