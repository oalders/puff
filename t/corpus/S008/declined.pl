my ( $path, $t, $files, $dest, @list, $x, $cmd, @args, @a, @b );
system "rm '$path'"; # expect: S008
system "make $t 2>&1"; # expect: S008
system "cp @$files $dest"; # expect: S008
system "prog --in=@list"; # expect: S008
system "a $x" || die; # expect: S008
system "$cmd"; # expect: S008
system "${x} y"; # expect: S008
system ". $x"; # expect: S008
system "FOO=$x make"; # expect: S008
system "cp a	b $x"; # expect: S008 - a tab
system "rm $ x"; # expect: S008 - $ x is $x
system "$cmd @args"; # expect: S008 - empty @args leaves one string
system "@a @b"; # expect: S008
system "exec $x y"; # expect: S008
