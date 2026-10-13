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
    {  print "hi\n"; }    # expect: B006
    {
        print "hi\n";
            # expect: B006
    }
    {   print "hi\n"; }    # expect: B006 B006
    my $z = 1;
    return $z;
}

# Every other block may be left empty.
sub other {
    if ( $_[0] ) {  }    # expect: B006
    for ( 1 .. 2 ) {  }    # expect: B006
    while ( $_[1] ) {  }    # expect: B006
    for ( 1 .. 2 ) { 1 } continue {  }    # expect: B006
    my $d = do {  };    # expect: B006
    my $e = eval {  };    # expect: B006
    my $z = 1;
    return ( $d, $e, $z );
}

sub body {  }    # expect: B006

1;
