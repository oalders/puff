use Digest::SHA qw(sha256_hex);
my ( $x, $id, %h, $obj );
$id = sha256_hex($x);
$id = sha256_hex( $x, $h{time} );
$id = sha256_hex( $x->time );
$id = sha256_hex("\$\$ $x");
$id = sha256_hex("$$x");
$id = $obj->md5_hex(time);
my $t = time;
