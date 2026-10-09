use strict;
use warnings;

my ( $input, $sep, $str ) = ( 'a.b', '.', 'a.b.c' );
my $h = { name => 'x' };

print "found\n" if $str =~ /^$input/; # expect: S019
my @fields = split /$sep/, $str; # expect: S019
( my $out = $str ) =~ s/$input|$h->{name}/X/g; # expect: S019 S019
my $q = qr{^$h->{name}\z}; # expect: S019
