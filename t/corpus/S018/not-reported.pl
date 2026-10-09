my ( $file, $cmd, @cmd, $obj, %cmd, $out );
system('ls');
system "make";
exec 'true';
system('ls -l');
system('ls -l /tmp');
system 'make install' or die;
exec "git log --oneline";
system('foo!');
system('a#b');
system("ls\t-l");
system("ls -l\n");
system('exec');
system('execute me');
system('.env');
system("ssh user\@host uptime");
system('cp a=b c');
system(<<'END');
ls -l
END
system( 'ls', '-l', $file );
system('ls -l | wc', '/tmp');
system(@cmd);
system { $cmd[0] } @cmd;
exec { 'sh' } 'sh', '-c', 'ls -l | wc';
system("tar xf $file");
system "tar xf " . $file;
system($cmd);
system 'ls -l' . $file;
system(<<"END");
ls $file | wc
END
$out = `ls $file | wc`;
$out = qx{ls $file};
$out = `hostname`;
$out = `ls -l`;
$out = qx(date);
$out = qx{git rev-parse HEAD};
$out = readpipe("ls $file");
$out = readpipe('date');
$out = readpipe('uname -a');
$obj->system('ls -l | wc');
$cmd{system} = 1;
my %h = ( exec => 'ls -l | wc' );
system('');
$out = `ssh user\@host uptime`;
