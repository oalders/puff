use strict;
use warnings;
use Fcntl qw( O_RDWR O_CREAT );
use File::Path qw( make_path mkpath );
use POSIX ();

my ( $file, $dir ) = ( 'f', 'd' );
my $zero = 0;
my $zeros = 00;
my $dec = 10;
my $float = 0.5;
my $hex = 0x1F;
my $bin = 0b101;
my $octal = oct('755');
my $str = '0755';
if (0) {
    chmod 0755, $file;
    chmod( 0644, $file, $dir );
    umask 022;
    umask(0027);
    mkdir $dir, 0755;
    mkdir( $dir, 0700 );
    POSIX::mkfifo( $file, 0600 );
    POSIX::mkfifo( join( q{/}, $dir, q{f} ), 0600 );
    mkdir join( q{/}, $dir, q{x} ), 0700;
    my %db;
    dbmopen %db, 'foo.db', 0600;
    sysopen my $fh, $file, O_RDWR | O_CREAT, 0666;
    sysopen( my $fh2, $file, O_RDWR, 0640 );
    mkpath( $dir, 0, 0711 );
    make_path( $dir, { mode => 0711 } );
    make_path( $dir, { chmod => 0711, 'perms' => 0700 } );
}
my $perm = ( stat $file )[2] & 07777;
my $new = 0666 & ~$zero;
my $other = 0666 &~ $zero;
$perm &= ~022;
$perm = $perm | 0100;
