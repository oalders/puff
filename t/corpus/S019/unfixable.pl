use strict;
use warnings;

my ( $input, $str, @x ) = ( 'a', 'b' );
my $ref = \$input;

print "1\n" if $str =~ /${ \ $input }/; # expect: S019
print "1\n" if $str =~ /$input[0]/; # expect: S019
print "1\n" if $str =~ /$input[a-z]/; # expect: S019
print "1\n" if $str =~ m-$input-; # expect: S019
print "1\n" if $str =~ /$ref->$*/; # expect: S019
