use strict;
use warnings;

sub interpolated {
    my $name = shift;
    my @list = (1, 2);
    my %h    = ( a => 1 );
    my $re   = 'x';
    my $doc  = 'y';
    my $code = 'z';
    print "Hello $name, @list[0,1] $h{a}\n";
    my $out = <<"END";
Doc: ${doc}
END
    (my $copy = $out) =~ s/x/$code/e;
    return $copy =~ /$re/;
}

sub elements {
    my @a = (1);
    my %h = ( k => 1 );
    my @b;
    return ( $a[0], @h{'k'}, $#b );
}

sub args {
    my ( $self, $c ) = @_;
    my $other = shift;
    my $third = $_[2];
    return 1;
}

sub guarded {
    my $guard = guard { cleanup() };
    my $txn   = $schema->txn_scope_guard;
    my $sg    = Scope::Guard->new( sub { 1 } );
    return 1;
}

sub closure {
    my $count = 0;
    return sub { $count++ };
}

sub nested {
    my $x = 1;
    if (1) {
        print $x;
    }
}

sub cast {
    my $ref = [];
    return ${ref};
}

our $global = 1;
my $file_level = 1;
print $file_level;
