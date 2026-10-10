package My::Child;

use Moo;
extends 'My::Base';

sub BUILD {
    my $self = shift;
    $self->next::method(@_); # TODO: drop once My::Base is Moo  # expect: M004
    $self->{ready} = 1;
}

package My::Other;

use Moose;
extends 'My::Base';

sub BUILD {
    my $self = shift;
    $self->SUPER::BUILD( # expect: M004
        @_
    );
    return;
}

sub DEMOLISH {
    my $self = shift;
	$self->next::method;	# tab indented  # expect: M004
}

1;
