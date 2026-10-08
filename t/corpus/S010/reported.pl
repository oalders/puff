use Digest::MD5 qw(md5_hex); # puff: ignore[S006]
use Digest::SHA qw(sha256_hex);
my ( $x, $id );
$id = md5_hex( time . $$ . rand ); # expect: S010
$id = md5_hex(time); # expect: S010
$id = sha256_hex( $x, localtime ); # expect: S010
$id = Digest::MD5::md5_hex("$$-$x"); # expect: S010
$id = sha256_hex join '', Time::HiRes::gettimeofday(), $x; # expect: S010
$id = md5_hex( rand() ); # expect: S010
$id = sha256_hex( CORE::time() ); # expect: S010
