use strict;
use warnings;

my ( $str, $fh ) = ( 'a', \*STDIN );

# A write to the short name counts for a package-qualified read.
our $short;
$main::short = qr/a/;
$::short     = qr/a/;
$short       = shift;
print "1\n" if $str =~ /\Q$main::short\E/; # expect: S019
print "1\n" if $str =~ /\Q$::short\E/; # expect: S019

# A write to a package-qualified name counts for the short name, in any
# spelling.
our $q1 = qr/a/;
our $q2 = qr/a/;
our $q3 = qr/a/;
our $q4 = qr/a/;
our $q5 = qr/a/;
$main::q1 = shift;
$::q2 = shift;
${main::q3} = shift;
{
    no strict;
    no warnings;
    ${::q4} = shift;
    $main'q5 = shift;
}
print "1\n" if $str =~ /\Q$q1\E\Q$q2\E\Q$q3\E\Q$q4\E\Q$q5\E/; # expect: S019 S019 S019 S019 S019

# foreach aliases its list, and a reference can be written through.
our $f1 = qr/a/;
our $f2 = qr/a/;
our $f3 = qr/a/;
our $r1 = qr/a/;
our $r2 = qr/a/;
for ($f1) { $_ = shift }
for my $v ( 1, $f2 ) { $v = shift }
s/^/x/ for $f3;
my $ref = \$r1;
my @refs = \( $str, $r2 );
print "1\n" if $str =~ /\Q$f1\E\Q$f2\E\Q$f3\E\Q$r1\E\Q$r2\E/; # expect: S019 S019 S019 S019 S019

# Builtins that change their arguments.
our $c1 = qr/a/;
our $c2 = qr/a/;
our $c3 = qr/a/;
our $c4 = qr/a/;
our $c5 = qr/a/;
our $c6 = qr/a/;
our $c7 = qr/a/;
chomp $c1;
chop( $str, $c2 );
read $fh, $c3, 10;
sysread( $fh, $c4, 10 );
open $c5, '<', $0 or die;
opendir( $c6, '.' ) or die;
print "1\n" if $str =~ /\Q$c1\E\Q$c2\E\Q$c3\E\Q$c4\E\Q$c5\E\Q$c6\E/; # expect: S019 S019 S019 S019 S019 S019

# Arguments that are not changed.
read $fh, $str, 10, $c7;
print "1\n" if $str =~ /$c7/;
