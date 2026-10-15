my ( $file, $cmd, %h, @arr );
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
