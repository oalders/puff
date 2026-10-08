use File::Temp qw(mktemp);
my ( $fh, $name );
open $fh, '>', "/tmp/report.$$"; # expect: S007
open $fh, '>', '/var/tmp/cache.db'; # expect: S007
my $f = '/tmp/' . $name; # expect: S007
$f = qq{/dev/shm/x}; # expect: S007
$f = mktemp('fooXXXX'); # expect: S007
$f = File::Temp::mktemp('fooXXXX'); # expect: S007
$f = POSIX::tmpnam(); # expect: S007
$f = tmpnam(); # expect: S007
my $g = tmpnam; # expect: S007
$f = scalar( tmpnam() ) . $$; # expect: S007
$f = scalar tmpnam(); # expect: S007
$f = tmpnam() . '.lock'; # expect: S007
$name->{x}{$f} = File::Temp::tmpnam(); # expect: S007
$f = $g = tmpnam(); # expect: S007
$f = File::Temp::tempnam( '/var/run', 'x' ); # expect: S007
my ( $lfh, $lname ) = POSIX::tmpnam(); # expect: S007
