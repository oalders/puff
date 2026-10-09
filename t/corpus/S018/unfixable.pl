my $out;
system('ls -l | wc -l'); # expect: S018
system 'make test > log.txt 2>&1'; # expect: S018
system('rm -f *.o'); # expect: S018
system('cd build && make'); # expect: S018
exec 'FOO=bar make'; # expect: S018
system('. ./env.sh'); # expect: S018
system('exec make'); # expect: S018
system('echo # not a comment'); # expect: S018
system('ls*'); # expect: S018
system("ls\t-l"); # expect: S018
system(q{grep 'x y' file}); # expect: S018
$out = `ls -l`; # expect: S018
$out = qx{git rev-parse HEAD}; # expect: S018
$out = qx'echo $HOME'; # expect: S018
$out = qx{ls \$HOME}; # expect: S018
$out = readpipe('date +%s'); # expect: S018
$out = CORE::readpipe('uname -a'); # expect: S018
system("ssh user\@host uptime"); # expect: S018
