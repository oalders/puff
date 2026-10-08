my $ua = LWP::UserAgent->new( ssl_opts => { verify_hostname => 1 } ); # expect: S005
$ua->ssl_opts( 'verify_hostname' => 1 ); # expect: S005
my $t = HTTP::Tiny->new( verify_SSL => 1 ); # expect: S005
my %o = ( SSL_verify_mode => SSL_VERIFY_PEER ); # expect: S005
%o = ( SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_PEER() ); # expect: S005
%o = ( "SSL_verify_mode" => 1 ); # expect: S005
$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 1; # expect: S005
local $ENV{'PERL_LWP_SSL_VERIFY_HOSTNAME'} = 1; # expect: S005
my $m = Mojo::UserAgent->new( insecure => 0 ); # expect: S005
$m->insecure(0); # expect: S005
my $ssh = Net::SSH::Perl->new( $host, strict_host_key_checking => 'no' ); # expect: S005
my $any = Net::SSH::Any->new( $host, strict_hostkeycheck => 0 ); # expect: S005
my $o = Net::OpenSSH->new( $host, master_opts => [ -o => 'StrictHostKeyChecking=no' ] ); # expect: S005
system 'ssh', '-o', "StrictHostKeyChecking no", $host; # expect: S005
