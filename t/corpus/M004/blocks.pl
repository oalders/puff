package My::Blocks;

use Moose;
extends 'My::Base';

# Perl reads an empty bare block as a hash, so `{ } my $x = 1;` does not
# compile. A call that is all that is in a bare block has no fix.
sub BUILD {
    my $self = shift;
    { $self->SUPER::BUILD(@_); } # expect: M004
    INIT_PARENT: { $self->SUPER::BUILD(@_); } # expect: M004
    {
        # only a comment is left
        $self->SUPER::BUILD(@_); # expect: M004
    }
    {
        $self->SUPER::BUILD(@_); # expect: M004
        $self->{bare} = 1;
    }
    my $x = 1;
}

# Every other block may be left empty.
sub DEMOLISH {
    my $self = shift;
    if ( $self->{a} ) { $self->SUPER::DEMOLISH(@_); } # expect: M004
    unless ( $self->{a} ) { $self->SUPER::DEMOLISH(@_); } # expect: M004
    if ( $self->{a} ) { 1 } elsif ( $self->{b} ) { $self->SUPER::DEMOLISH(@_); } # expect: M004
    if ( $self->{a} ) { 1 } else { $self->SUPER::DEMOLISH(@_); } # expect: M004
    for ( 1 .. 2 ) { $self->SUPER::DEMOLISH(@_); } # expect: M004
    foreach my $i ( 1 .. 2 ) { $self->SUPER::DEMOLISH(@_); } # expect: M004
    while ( $self->{a} ) { $self->SUPER::DEMOLISH(@_); } # expect: M004
    until ( $self->{a} ) { $self->SUPER::DEMOLISH(@_); } # expect: M004
    LOOP: for ( 1 .. 2 ) { $self->SUPER::DEMOLISH(@_); } # expect: M004
    for ( 1 .. 2 ) { 1 } continue { $self->SUPER::DEMOLISH(@_); } # expect: M004
    my $x = 1;
}

package My::Empty;

use Moose;
extends 'My::Base';

my $self = __PACKAGE__;

sub BUILD { $self->SUPER::BUILD(@_); } # expect: M004

1;
