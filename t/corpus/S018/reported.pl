my $out;
system('ls -l | wc -l'); # expect: S018
system 'make test > log.txt 2>&1'; # expect: S018
system('rm -f *.o'); # expect: S018
system('cd build && make'); # expect: S018
exec 'FOO=bar make'; # expect: S018
system('. ./env.sh'); # expect: S018
system('exec make'); # expect: S018
system('  exec make'); # expect: S018
system('echo # not a comment; date'); # expect: S018
system('ls*'); # expect: S018
system(q{grep 'x y' file}); # expect: S018
system("ls\n-l"); # expect: S018
CORE::system(q{tar cf - lib | gzip > out.tgz}); # expect: S018
my $rc = system( 'cp', '-r', 'a', 'b' ) == 0 && system('rm -rf build/*') == 0; # expect: S018
system(('ls -l | wc')); # expect: S018
print STDERR system 'ls | wc'; # expect: S018
system(<<'END'); # expect: S018
ls -l | wc -l
END
system(<<"END"); # expect: S018
make
make install
END
$out = `ls -l | wc -l`; # expect: S018
$out = qx{git rev-parse HEAD 2>/dev/null}; # expect: S018
$out = qx'echo $HOME'; # expect: S018
$out = qx{ls \$HOME}; # expect: S018
$out = readpipe('date +%s; uname'); # expect: S018
$out = CORE::readpipe('uname -a > x'); # expect: S018
$out = `ssh user\@host uptime | head`; # expect: S018
system "FOO=1 ls"; # expect: S018
system "a=b"; # expect: S018
system "  . foo"; # expect: S018
system "ls\n\n"; # expect: S018
system "ls\\x24 | wc"; # expect: S018
system "ls 2>&1 | wc"; # expect: S018
system "ls\n 2>&1"; # expect: S018
system "ls 2>&1x"; # expect: S018
system "ls>2>&1"; # expect: S018
