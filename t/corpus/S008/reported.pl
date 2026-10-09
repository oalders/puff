my ( $file, $cmd, $fh, $ref );
system("tar xf $file"); # expect: S008
system "tar xf " . $file; # expect: S008
system($cmd); # expect: S008
exec "git log $ref"; # expect: S008
CORE::system($cmd); # expect: S008
my $out = `ls $file`; # expect: S008
$out = qx{ls $file}; # expect: S008
$out = readpipe("ls $file"); # expect: S008
open( $fh, '-|', "git log $ref" ) or die; # expect: S008
open $fh, '|-', $cmd or die; # expect: S008
$out = qx(ls @{[ $file ]}); # expect: S008
my ( $x, @a );
$out = qx(ls $x); # expect: S008
$out = qx{ls @a}; # expect: S008
