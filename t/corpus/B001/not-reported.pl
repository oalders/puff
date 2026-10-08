use strict;
use warnings;

my $re  = qr/abc/;
my $str = 'ABC';
print "1\n" if $str =~ /$re/;
print "2\n" if $str =~ /$re/g;
print "3\n" if $str =~ /^$re/i;
print "4\n" if $str =~ /$re$re/i;
( my $copy = $str ) =~ s/$re/x/r;

my $text = 'abc';
print "5\n" if $str =~ /$text/i;

my $mixed = qr/a/;
$mixed = 'b';
print "6\n" if $str =~ /$mixed/i;

my $grown = qr/a/;
$grown .= 'b';
print "7\n" if $str =~ /$grown/i;

my ( $listed ) = ( qr/a/ );
print "8\n" if $str =~ /$listed/i;

my $built = qr/a/ . 'b';
print "9\n" if $str =~ /$built/i;

my %h = ( re => qr/a/ );
print "10\n" if $str =~ /$h{re}/i;

my $unknown;
print "11\n" if $str =~ /$unknown/i;
