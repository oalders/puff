use v5.36;
use English;
no strict q{refs};
${ *{"main::O"."RS"} } = "!";
print "hello\n"; # expect: U002
