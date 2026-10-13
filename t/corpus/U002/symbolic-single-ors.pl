use v5.10;
*{'main::ORS'} = \'x';
print "hello\n"; # expect: U002
