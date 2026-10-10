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

package My::SameLine;

use Moose;
extends 'My::Base';

my $self;

sub BUILD { # set up in My::Base  # expect: M004
}

sub DEMOLISH {
    my $self = shift; # after a statement  # expect: M004
}

package My::Trailing;

use Moo;
extends 'My::Base';

sub BUILD {
    my $self = shift;
}

1;
