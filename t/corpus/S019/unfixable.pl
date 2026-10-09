use strict;
use warnings;

my ( $input, $str, @x ) = ( 'a', 'b' );
my $ref = \$input;

print "1\n" if $str =~ /${ \ $input }/; # expect: S019
print "1\n" if $str =~ /$input[0]/; # expect: S019
print "1\n" if $str =~ /$input[a-z]/; # expect: S019
print "1\n" if $str =~ m-$input-; # expect: S019
print "1\n" if $str =~ /$ref->$*/; # expect: S019

# Reported with no fix: a quantifier follows, a character class, a /x comment.
print "1\n" if $str =~ /$input+/; # expect: S019
print "1\n" if $str =~ /a$input*?/; # expect: S019
print "1\n" if $str =~ /$input?/; # expect: S019
print "1\n" if $str =~ /$input{2}/; # expect: S019
print "1\n" if $str =~ /${input}{2,3}/; # expect: S019
print "1\n" if $str =~ /$input +/x; # expect: S019
print "1\n" if $str =~ /[$input]/; # expect: S019
print "1\n" if $str =~ /[]$input]/; # expect: S019
print "1\n" if $str =~ /[[:alpha:]$input]/; # expect: S019
print "1\n" if $str =~ /
    a # $input # expect: S019
/x;
