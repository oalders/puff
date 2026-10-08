my ( $file, $cmd, @cmd, $fh, $ref, $obj, %cmd );
system( 'tar', 'xf', $file );
system('make test');
system "make install";
system(@cmd);
system @cmd;
system @{$cmd};
system { $cmd[0] } @cmd;
exec( $cmd, '--version' );
my $out = `ls -l`;
$out = qx'ls $HOME';
$out = qx{ls \$HOME};
open( $fh, '-|', 'git', 'log', $ref ) or die;
open( $fh, '<', $file ) or die;
open( $fh, '-|', 'git log' ) or die;
$obj->system($cmd);
$cmd{system} = 1;
sub exec { 1 }
