use strict;
use warnings;
use Fcntl qw( O_RDWR O_CREAT );
use File::Path qw( make_path mkpath );
use POSIX ();

my ( $file, $dir, $p ) = ( 'f', 'd', undef );
if (0) {
    chmod 0755, $file; # expect: B010
    chmod( 0644, $file, $dir ); # expect: B010
    CORE::chmod 0600, $file; # expect: B010
    chmod 01777, $dir; # expect: B010
    umask 022; # expect: B010
    umask(077); # expect: B010
    umask 027; umask 0277; # expect: B010
    mkdir $dir, 0777; # expect: B010
    mkdir( $dir, 0700 ); # expect: B010
    mkdir join( q{/}, $dir, q{x} ), 0711; # expect: B010
    sysopen my $fh, $file, O_RDWR | O_CREAT, 0666; # expect: B010
    sysopen( my $fh2, $file, O_RDWR, 0640 ); # expect: B010
    POSIX::mkfifo( $file, 0600 ); # expect: B010
    my %db;
    dbmopen %db, 'foo.db', 0644; # expect: B010
    mkpath( $dir, 0, 0711 ); # expect: B010
    make_path( $dir, { mode => 0711 } ); # expect: B010
    make_path $dir, { chmod => 0755, verbose => 1 }; # expect: B010
    File::Path::make_path( $dir, { 'mask' => 22 } ) if 0;
    File::Path::make_path( $dir, { 'mask' => 0755 } ); # expect: B010
    mkpath( [$dir], { mode => 0700 } ); # expect: B010
    $p->chmod(0755); # expect: B010
    $p->mkdir( { mode => 0700 } ); # expect: B010
    path($dir)->mkpath( { mask => 0750, chmod => 0750 } ); # expect: B010 B010
    my @f;
    chmod 0755, sort @f; # expect: B010
    chmod 0755 => $file; # expect: B010
    chmod 0755; # expect: B010
    # Known false positive: any class's ->chmod is checked, not just
    # Path::Tiny's, since method calls cannot be typed.
    my $obj = bless {}, 'Not::Path::Tiny';
    $obj->chmod(0755); # expect: B010
}

sub path { return shift }
