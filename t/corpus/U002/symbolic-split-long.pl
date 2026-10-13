use v5.10;
use English;
${"main::OUTPUT_" . "RECORD_SEPARATOR"} = "!";
print "hello\n"; # expect: U002
