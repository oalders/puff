use v5.36;

my $x     = 1;
my @items = ( 1, 2 );
my %opt;

for my $item (@items) {
    my $item = $item * 2; # expect: B008
    print $item;
}

foreach my $x (@items) { # expect: B008
    print $x;
}

sub uses_file_lexical {
    my $x = 2; # expect: B008
    return $x;
}

sub signature ( $self, $x ) { # expect: B008
    return $self + $x;
}

{
    my $x = $x + 1; # expect: B008
    print $x;
}

if ( my $found = shift ) {
    my $found = 1; # expect: B008
    print $found;
}
else {
    my ( $found, %opt ) = ( 2, () ); # expect: B008 B008
    print $found, %opt;
}

while ( my $line = shift ) {
    for my $line ( 1, 2 ) { # expect: B008
        print $line;
    }
}

my $cb = sub {
    my @items = (3); # expect: B008
    return @items;
};

my $cb2 = sub ($x) { return $x }; # expect: B008

sub outer {
    my $name = 'a';
    for ( 1, 2 ) {
        state $name = 'b'; # expect: B008
        print $name;
    }
    return $name;
}

our $setting = 1;
{
    my $setting = 2; # expect: B008
    print $setting;
}

{
    use feature 'try';
    no warnings 'experimental::try';
    my $e;
    try { die } catch ($e) { print $e } # expect: B008
    try { die }
    catch ($caught) {
        try { die } catch ($caught) { print $caught } # expect: B008
    }
}
