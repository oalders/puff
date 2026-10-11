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

package My::SameLine;

use Moose;
extends 'My::Base';

my $self;

sub BUILD { $self->SUPER::BUILD(@_); # set up in My::Base  # expect: M004
}

sub DEMOLISH {
    my $self = shift; $self->SUPER::DEMOLISH(@_); # after a statement  # expect: M004
}

package My::Trailing;

use Moo;
extends 'My::Base';

sub BUILD {
    my $self = shift; $self->next::method( # expect: M004
        @_
    );
}

1;
