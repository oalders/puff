package My::Blocks;

use Moose;
extends 'My::Base';

# Perl reads an empty bare block, or one that starts like a hash, as a hash,
# so `{ } my $x = 1;` does not compile. PPI reads one that starts with `;` as
# a hash. A call whose removal would leave such a block has no fix.
sub BUILD {
    my $self = shift;
    { $self->SUPER::BUILD(@_); } # expect: M004
    INIT_PARENT: { $self->SUPER::BUILD(@_); } # expect: M004
    { $self->SUPER::BUILD(@_) } # expect: M004
    { { $self->SUPER::BUILD(@_); } } # expect: M004
    { $self->SUPER::BUILD(@_);; } # expect: M004
    { $self->SUPER::BUILD(@_); $self->next::method(@_); } # expect: M004 M004
    AGAIN: { $self->SUPER::BUILD(@_); $self->SUPER::BUILD(@_); } # expect: M004 M004
    {
        $self->SUPER::BUILD(@_); # expect: M004
        # a comment between the calls
        $self->SUPER::BUILD(@_); # expect: M004
    }
    {
        # only a comment is left
        $self->SUPER::BUILD(@_); # expect: M004
    }
    { $self->SUPER::BUILD(@_); bare => 1, $self->{bare} = 1; } # expect: M004
    { $self->SUPER::BUILD(@_); "bare", $self->{bare} = 1; } # expect: M004
    {
        # expect: M004
        # expect: M004
        $self->{bare} = 1;
    }
    {
        $self->{bare} = 1;
        # expect: M004
        # expect: M004
    }
    my $x = 1;

    # PPI reads this block as a hash, and the code after it as part of it.
    { ; $self->SUPER::BUILD(@_) } # expect: M004
}

# Every other block may be left empty.
sub DEMOLISH {
    my $self = shift;
    if ( $self->{a} ) { } # expect: M004
    unless ( $self->{a} ) { } # expect: M004
    if ( $self->{a} ) { 1 } elsif ( $self->{b} ) { } # expect: M004
    if ( $self->{a} ) { 1 } else { } # expect: M004
    for ( 1 .. 2 ) { } # expect: M004
    foreach my $i ( 1 .. 2 ) { } # expect: M004
    while ( $self->{a} ) { } # expect: M004
    until ( $self->{a} ) { } # expect: M004
    LOOP: for ( 1 .. 2 ) { } # expect: M004
    for ( 1 .. 2 ) { 1 } continue { } # expect: M004
    my $x = 1;
}

package My::Empty;

use Moose;
extends 'My::Base';

my $self = __PACKAGE__;

sub BUILD { } # expect: M004

1;
