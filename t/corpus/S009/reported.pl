my ( $f, $p );
chmod 0777, $f; # expect: S009
chmod( 0666, $f ); # expect: S009
CORE::chmod 0o777, $f; # expect: S009
chmod 0x1ff, $f; # expect: S009
$p->chmod(0777); # expect: S009
$p->chmod('o+w'); # expect: S009
$p->chmod("u+x,a+rw"); # expect: S009
umask 0; # expect: S009
umask(0020); # expect: S009
chmod 777, $f; # expect: S009
chmod( 666, $f ); # expect: S009
$p->chmod(666); # expect: S009
umask 20; # expect: S009
umask 770; # expect: S009
chmod 755, $f; # expect: S009
umask 77; # expect: S009
chmod 511, $f; # expect: S009
chmod 750, $f; # expect: S009
