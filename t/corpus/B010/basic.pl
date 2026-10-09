use strict;
use warnings;
use Fcntl qw( O_RDWR O_CREAT );
use File::Path qw( make_path mkpath );
use POSIX ();

my ( $file, $dir, $p ) = ( 'f', 'd', undef );
if (0) {
    chmod 755, $file; # expect: B010
    chmod( 644, $file, $dir ); # expect: B010
    CORE::chmod 600, $file; # expect: B010
    chmod 1777, $dir; # expect: B010
    umask 22; # expect: B010
    umask(77); # expect: B010
    umask 027; umask 277; # expect: B010
    mkdir $dir, 777; # expect: B010
    mkdir( $dir, 700 ); # expect: B010
    mkdir join( q{/}, $dir, q{x} ), 711; # expect: B010
    sysopen my $fh, $file, O_RDWR | O_CREAT, 666; # expect: B010
    sysopen( my $fh2, $file, O_RDWR, 640 ); # expect: B010
    POSIX::mkfifo( $file, 600 ); # expect: B010
    my %db;
    dbmopen %db, 'foo.db', 644; # expect: B010
    mkpath( $dir, 0, 711 ); # expect: B010
    make_path( $dir, { mode => 711 } ); # expect: B010
    make_path $dir, { chmod => 755, verbose => 1 }; # expect: B010
    File::Path::make_path( $dir, { 'mask' => 22 } ) if 0;
    File::Path::make_path( $dir, { 'mask' => 755 } ); # expect: B010
    mkpath( [$dir], { mode => 700 } ); # expect: B010
    $p->chmod(755); # expect: B010
    $p->mkdir( { mode => 700 } ); # expect: B010
    path($dir)->mkpath( { mask => 750, chmod => 750 } ); # expect: B010 B010
}

sub path { return shift }
