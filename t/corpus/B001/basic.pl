use strict;
use warnings;

my $re = qr/abc/;
my $str = 'ABC';
print "match\n" if $str =~ /$re/i; # expect: B001
print "match\n" if $str =~ m{$re}msx; # expect: B001
print "match\n" if $str =~ m/${re}/gi; # expect: B001
( my $copy = $str ) =~ s/$re/'x'/gie; # expect: B001
my @parts = split /$re/i, $str; # expect: B001

our $WORD;
$WORD = qr/\w+/i;
print "word\n" if $str =~ /$WORD/i; # expect: B001

my $maybe;
$maybe //= qr/x/;
print "x\n" if $str =~ /$maybe/s; # expect: B001
