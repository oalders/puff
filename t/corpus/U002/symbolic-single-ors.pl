use v5.36;
no strict q{refs};
*{'main::ORS'} = \'x';
print "hello\n"; # expect: U002
