my ( $out, $src, $date, $prog, $arg );
system 'tar', '-czf', $out, $src; # expect: S008
system 'tar', '-czf', "backup-$date.tgz", ${src}; # expect: S008
CORE::exec($prog, $arg); # expect: S008
