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
