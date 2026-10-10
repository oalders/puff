use v5.36;

sub ready { return $_[0] }
sub go    { return 1 }

go() unless ready(1);

unless ( ready(1) ) {
    go();
}

if ( ready(1) ) {
    go();
}
else {
    go();
}

my $unless = 1;
my %h = ( unless => 1, else => 2 );
