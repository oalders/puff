my ( $file, $cmd, %h, @arr, $host, $x, $y );
system "ls $file | wc -l"; # expect: S008
system "rm '$file'"; # expect: S008
system "ls $h{x}"; # expect: S008
system "ls @arr"; # expect: S008
system "$cmd"; # expect: S008
system <<"END"; # expect: S008
ls $file
END
system "ls " . $file; # expect: S008
system $cmd; # expect: S008
system "make $file 2>&1"; # expect: S008
system "sh -c $cmd"; # expect: S008
system "/usr/bin/ssh $host $cmd"; # expect: S008
system "printf %s\\n $x"; # expect: S008
system "ls $x->[0] $y"; # expect: S008
system "$x=foo bar"; # expect: S008
