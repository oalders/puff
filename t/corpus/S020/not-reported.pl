use v5.36;

my $ua   = LWP::UserAgent->new( timeout => 10 );
my $http = HTTP::Tiny->new( timeout => 60 );
my $mech = WWW::Mechanize->new( timeout => 30, autocheck => 1 );
my $furl = Furl->new( timeout => 5 );
my $raw  = Furl::HTTP->new( 'timeout', 5 );
my $mojo = Mojo::UserAgent->new( request_timeout => 30 );
my $mi   = Mojo::UserAgent->new( { inactivity_timeout => 20, connect_timeout => 5 } );
my $ind  = new LWP::UserAgent( timeout => 10 );
my $last = LWP::UserAgent->new( timeout => 600, timeout => 20 );

# Values the rule cannot read.
my $t   = 300;
my $var = LWP::UserAgent->new( timeout => $t );
my $exp = HTTP::Tiny->new( timeout => 2 * $t );
my $neg = HTTP::Tiny->new( timeout => -1 );
my %opts;
my $opt = LWP::UserAgent->new(%opts);
my $ref = Mojo::UserAgent->new( \%opts );
my $mix = LWP::UserAgent->new( %opts, timeout => 0 );

# A setter later in the same block.
my $later = LWP::UserAgent->new;
$later->timeout(15);
my $tiny = HTTP::Tiny->new;
$tiny->timeout($t);

sub client {
    my $c = Mojo::UserAgent->new;
    $c->request_timeout(10)->connect_timeout(5);
    return $c;
}

our $global = LWP::UserAgent->new( agent => 'x' );
if ($global) { $global->timeout(30) }

# A chained setter.
my $chained = Mojo::UserAgent->new->inactivity_timeout(20);
my $both    = Mojo::UserAgent->new( connect_timeout => 3 )->request_timeout(10);

# Not a constructor of a known client.
my $other = LWP::Simple->new;
my $class = 'LWP::UserAgent';
my $dyn   = $class->new;
LWP::UserAgent->can('new');
my $name = LWP::UserAgent::;
