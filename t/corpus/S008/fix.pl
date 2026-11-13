my ( $out, $src, $file, $ref, $date, @files, $dest, $x, $y );
system "tar -czf $out $src"; # expect: S008
system("tar xf $file"); # expect: S008
system qq{tar xf $file}; # expect: S008
exec "git log $ref"; # expect: S008
CORE::system "tar xf $file"; # expect: S008
system 1, "tar $x $y"; # expect: S008
system 0, "tar xf $file"; # expect: S008
system "tar czf backup-$date.tgz $src"; # expect: S008
system "cp @files $dest"; # expect: S008
system "  cp  $x   $y "; # expect: S008
system "cp a b $x"; # expect: S008 - NBSP in a word
system "mv $1 $2x"; # expect: S008
CORE::exec qq{git log $ref}; # expect: S008
system "cp $Foo::src $Foo::dest"; # expect: S008
system("tar xf $file") == 0 or die; # expect: S008
