use v5.36;

my $x = 1;
my $x = 2; # expect: B007
my ( $first, $second ) = ( 1, 2 );
my ( $second, $third ) = ( 3, 4 ); # expect: B007
my ( $dup, $dup ) = ( 5, 6 ); # expect: B007
my @list;
my @list; # expect: B007
state %seen;
state %seen; # expect: B007
our $global;
my $global; # expect: B007
my $total = 0;
my $total = $total + 1; # expect: B007

sub with_signature ( $self, $count = 0 ) {
    my $count = 1; # expect: B007
    return $self + $count;
}

sub body {
    my $v = 1;
    if ($v) { print $v }
    my $v = 2; # expect: B007
    return $v;
}

if ( my $match = shift ) {
    print $match;
}
elsif ( my $match = shift ) { # expect: B007
    print $match;
}

package Foo;
our $VERSION = '1.0';
our $VERSION = '1.1'; # expect: B007

package Alternate::A;
our $shared = 1;

package Alternate::B;
our $shared = 2;

package Alternate::A;
our $shared = 3; # expect: B007
