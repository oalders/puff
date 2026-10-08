use Digest::MD5 qw(md5_hex); # expect: S006
require Digest::SHA1; # expect: S006
use Digest::SHA qw(sha1_hex sha256_hex); # expect: S006
use Digest::SHA 'sha1'; # expect: S006
my ( $x, $p, $s );
my $h = Digest::SHA::sha1_hex($x); # expect: S006
my $d = Digest->new('MD5'); # expect: S006
$d = Digest->new("SHA-1"); # expect: S006
$d = Digest::SHA->new; # expect: S006
$d = Digest::SHA->new(1); # expect: S006
$d = Digest::SHA->new('sha1'); # expect: S006
my $c = crypt( $p, $s ); # expect: S006
