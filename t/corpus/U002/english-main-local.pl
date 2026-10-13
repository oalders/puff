use v5.36;
use English;
local $::OUTPUT_RECORD_SEPARATOR = q{};
print "x\n"; # expect: U002
