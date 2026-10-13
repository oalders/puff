use v5.36;
use English;
my $s = q{a};
$s =~ s/a/$main::OUTPUT_RECORD_SEPARATOR = ''/e;
print "x\n"; # expect: U002
