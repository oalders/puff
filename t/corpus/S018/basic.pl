system('ls -l /tmp'); # expect: S018
system 'make install' or die; # expect: S018
exec "git log --oneline"; # expect: S018
CORE::system(q{tar cf out.tar lib}); # expect: S018
my $rc = system( 'cp', '-r', 'a', 'b' ) == 0 && system('rm -rf build/tmp') == 0; # expect: S018
