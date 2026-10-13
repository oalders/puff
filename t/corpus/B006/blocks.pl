use strict;
use warnings;

# Perl reads an empty bare block, or one that starts like a hash, as a hash,
# so `{ } my $z = 1;` does not compile. A declaration whose removal would
# leave such a block has no fix.
sub bare {
    { my $unused; }    # expect: B006
    LABEL: { my $unused; }    # expect: B006
    { my $one; my $two; }    # expect: B006 B006
    {
        # only a comment is left
        my $unused;    # expect: B006
    }
    { my $unused; bare => 1, print "hi\n"; }    # expect: B006
    { my $unused; "bare", print "hi\n"; }    # expect: B006
    my $z = 1;
    return $z;
}

# A bare block that keeps a statement is still a block.
sub kept {
    { my $unused; print "hi\n"; }    # expect: B006
    {
        print "hi\n";
        my $unused;    # expect: B006
    }
    { my $one; my $two; print "hi\n"; }    # expect: B006 B006
    my $z = 1;
    return $z;
}

# Every other block may be left empty.
sub other {
    if ( $_[0] ) { my $unused; }    # expect: B006
    for ( 1 .. 2 ) { my $unused; }    # expect: B006
    while ( $_[1] ) { my $unused; }    # expect: B006
    for ( 1 .. 2 ) { 1 } continue { my $unused; }    # expect: B006
    my $d = do { my $unused; };    # expect: B006
    my $e = eval { my $unused; };    # expect: B006
    my $z = 1;
    return ( $d, $e, $z );
}

sub body { my $unused; }    # expect: B006

1;
