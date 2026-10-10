use strict;
use warnings;
use Fcntl qw( O_RDWR O_CREAT );
use File::Path qw( make_path );

my ( $file, $dir, $p, $mode ) = ( 'f', 'd', undef, 0 );
my $count = 755;
my %opts = ( mode => 755 );
if (0) {
    chmod 0755, $file;
    chmod 0o755, $file;
    chmod 0x1ed, $file;
    chmod 0b111101101, $file;
    chmod 789, $file;
    chmod 758, $file;
    chmod 75, $file;
    chmod 7, $file;
    chmod 75555, $file;
    chmod 7_55, $file;
    chmod 755.0, $file;
    chmod oct('755'), $file;
    chmod oct(755), $file;
    chmod $mode, $file;
    chmod 700 + 55, $file;
    chmod -755, $file;
    chmod $count, 755;
    umask 0;
    umask 2;
    umask 0022;
    umask 88;
    umask $mode;
    mkdir 755;
    mkdir 755, $dir;
    $p->mkdir( $dir, 755 );
    $p->mkpath( $dir, 755 );

    # Decimal values of common modes and umasks are taken as deliberate.
    mkdir "x", 511;
    mkdir $dir, 504;
    chmod 511, $file;
    chmod 493, $file;
    chmod 457, $file;
    chmod 420, $file;
    umask 18;
    umask 23;
    umask 63;
    mkdir $dir, 0755;
    mkdir $dir, 75;
    sysopen my $fh, $file, 755;
    make_path( $dir, { mode => 0755 } );
    make_path( $dir, { mode => 75 } );
    make_path( $dir, { verbose => 755 } );
    make_path( $dir, { mode => 755 + 0 } );
    make_path( $dir, foo( { mode => 755 } ) );
    $p->chmod('755');
    $p->chmod("0755");
    $p->chmod('u+x');
    $p->chmod(0755);
    $p->chmod( 755, $file );
    $p->mkdir(755);
    $p->mkdir( { mode => 0755 } );
    $p->remove_tree( { mode => 755 } );
    $p->size(755);
    foo( mode => 755 );
    print 755, "\n";
}

sub foo { return shift }
