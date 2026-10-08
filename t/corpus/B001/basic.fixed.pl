use strict;
use warnings;

my $re = qr/abc/;
my $str = 'ABC';
print "match\n" if $str =~ /$re/; # expect: B001
print "match\n" if $str =~ m{$re}; # expect: B001
print "match\n" if $str =~ m/${re}/g; # expect: B001
( my $copy = $str ) =~ s/$re/'x'/ge; # expect: B001
my @parts = split /$re/, $str; # expect: B001

our $WORD;
$WORD = qr/\w+/i;
print "word\n" if $str =~ /$WORD/; # expect: B001

my $maybe;
$maybe //= qr/x/;
print "x\n" if $str =~ /$maybe/; # expect: B001
