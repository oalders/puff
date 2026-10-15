my ( $out, $src, $date, $prog, $arg, $dir );
system 'tar', '-czf', $out, $src; # expect: S008
system 'tar', '-czf', "backup-$date.tgz", ${src}; # expect: S008
CORE::exec($prog, $arg); # expect: S008
system 'ls', "$1st", $dir; # expect: S008
