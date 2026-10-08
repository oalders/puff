use strict;
use warnings;

sub total {
    my @items = @_;
    my $total = 0;    # expect: B006
    my $sum   = 0;
    $sum += $_ for @items;
    return $sum;
}

sub parse {
    my ($line) = @_;
    my ( $key, $value, $comment ) = split /:/, $line;    # expect: B006
    return { $key => $value };
}

sub unused_rest {
    my ( $name, @rest ) = split /,/, shift;    # expect: B006
    return $name;
}

sub empty {
    my $unused;    # expect: B006
    my ( $a1, $b1 );    # expect: B006 B006
    return;
}

sub first_unused {
    my ( $skip, $keep ) = split / /, shift;    # expect: B006
    return $keep;
}
