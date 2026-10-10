package My::Child;

use Moo;
extends 'My::Base';

sub BUILD {
    my $self = shift;
    # TODO: drop once My::Base is Moo  # expect: M004
    $self->{ready} = 1;
}

package My::Other;

use Moose;
extends 'My::Base';

sub BUILD {
    my $self = shift;
    return;
}

sub DEMOLISH {
    my $self = shift;
	# tab indented  # expect: M004
}

1;
