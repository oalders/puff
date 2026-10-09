use v5.36;

my $ua   = LWP::UserAgent->new;                       # expect: S020
my $http = HTTP::Tiny->new;                           # expect: S020
my $mech = WWW::Mechanize->new( autocheck => 1 );     # expect: S020
my $furl = Furl->new( agent => 'x' );                 # expect: S020
my $raw  = Furl::HTTP->new();                         # expect: S020
my $mojo = Mojo::UserAgent->new;                      # expect: S020

# Too long, or zero.
my $slow  = LWP::UserAgent->new( timeout => 180 );    # expect: S020
my $none  = HTTP::Tiny->new( timeout => 0 );          # expect: S020
my $quote = Furl->new( timeout => '300' );            # expect: S020
my $last  = LWP::UserAgent->new( timeout => 10, timeout => 61 );    # expect: S020
my $href  = Mojo::UserAgent->new( { request_timeout => 600 } );     # expect: S020
my $zero  = Mojo::UserAgent->new( inactivity_timeout => 0 );        # expect: S020
my $conn  = Mojo::UserAgent->new( request_timeout => 10, connect_timeout => 120 );    # expect: S020

# connect_timeout alone does not bound the transfer.
my $connect = Mojo::UserAgent->new( connect_timeout => 5 );    # expect: S020

# Indirect object syntax.
my $indirect = new LWP::UserAgent;    # expect: S020

# Not stored in a plain scalar, so a later setter cannot be found.
my $res = LWP::UserAgent->new->get('https://example.com/');    # expect: S020
my %h;
$h{ua} = LWP::UserAgent->new;    # expect: S020
$h{ua}->timeout(10);

# A setter with a bad value.
my $bad = LWP::UserAgent->new;    # expect: S020
$bad->timeout(0);
my $chained = Mojo::UserAgent->new->request_timeout(3600);    # expect: S020

# A setter on another variable of the same name does not count.
my $outer = LWP::UserAgent->new;    # expect: S020
{
    my $outer = HTTP::Tiny->new( timeout => 5 );
    $outer->timeout(10);
}

# A setter before the constructor does not count.
my $early;
$early->timeout(10);
$early = HTTP::Tiny->new;    # expect: S020

# A getter is not a setter.
my $getter = LWP::UserAgent->new;    # expect: S020
say $getter->timeout;

# A setter in another block does not count.
sub make { my $client = LWP::UserAgent->new; return $client }    # expect: S020
sub use_it { my $client = shift; $client->timeout(5) }

# Mojo's connect_timeout setter alone does not count.
my $mc = Mojo::UserAgent->new;    # expect: S020
$mc->connect_timeout(5);
