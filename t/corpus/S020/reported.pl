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

# A setter in a nested sub, a condition or with a statement modifier does
# not count.
our $global = LWP::UserAgent->new( agent => 'x' );    # expect: S020
if ($global) { $global->timeout(30) }
my $nested = LWP::UserAgent->new;    # expect: S020
sub set_nested { $nested->timeout(10) }
my $cond = HTTP::Tiny->new;    # expect: S020
$cond->timeout(10) if $global;
my $loop = HTTP::Tiny->new;    # expect: S020
for ( 1 .. 2 ) { $loop->timeout(10) }

# A bad setter value is reported even after a good constructor value.
my $reset = LWP::UserAgent->new( timeout => 5 );    # expect: S020
$reset->timeout(0);
my $huge = Mojo::UserAgent->new( request_timeout => 5 );    # expect: S020
$huge->connect_timeout(600);
my $died = LWP::UserAgent->new or die 'no client';    # expect: S020
$died->timeout(120);

# undef, negative and quoted values.
my $undef_new    = LWP::UserAgent->new( timeout => undef );    # expect: S020
my $tiny_undef   = HTTP::Tiny->new( timeout => undef );        # expect: S020
my $undef_setter = WWW::Mechanize->new;                        # expect: S020
$undef_setter->timeout(undef);
my $tiny_off = HTTP::Tiny->new( timeout => 5 );    # expect: S020
$tiny_off->timeout(undef);
my $neg    = HTTP::Tiny->new( timeout => -5 );       # expect: S020
my $spaced = LWP::UserAgent->new( timeout => - 1 );  # expect: S020
my $qneg   = Furl->new( timeout => '-5' );           # expect: S020
my $exp    = LWP::UserAgent->new( timeout => '1e9' );    # expect: S020
my $inf    = LWP::UserAgent->new( timeout => 'inf' );    # expect: S020
my $nan    = LWP::UserAgent->new( timeout => 'nan' );    # expect: S020

# Furl has no timeout setter.
my $fs = Furl->new;    # expect: S020
$fs->timeout(5);
my $fc = Furl::HTTP->new->timeout(5);    # expect: S020

# A setter after the name is assigned again belongs to the new client.
my $replaced = LWP::UserAgent->new;    # expect: S020
$replaced = LWP::UserAgent->new( timeout => 5 );
$replaced->timeout(5);
