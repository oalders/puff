use strict;
use warnings;

my ( $input, $sep, $str ) = ( 'a.b', '.', 'a.b.c' );
my $h = { name => 'x' };

print "found\n" if $str =~ /^\Q$input\E/; # expect: S019
my @fields = split /\Q$sep\E/, $str; # expect: S019
( my $out = $str ) =~ s/\Q$input\E|\Q$h->{name}\E/X/g; # expect: S019 S019
my $q = qr{^\Q$h->{name}\E\z}; # expect: S019
