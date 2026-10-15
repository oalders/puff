my ( $out, $src, $date, $prog, $arg, $dir, $x );
system "tar -czf $out $src"; # expect: S008
system qq{tar -czf backup-$date.tgz ${src}}; # expect: S008
CORE::exec("$prog $arg"); # expect: S008
system "ls $1st $dir"; # expect: S008
system "ls $Pkg::dir $x"; # expect: S008
