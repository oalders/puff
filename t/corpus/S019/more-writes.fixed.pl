use strict;
use warnings;

my ( $str, $fh, $in, $c ) = ( 'a', \*STDIN, 'b', 1 );

# substr with a replacement changes its first argument; without one it
# does not.
our $s1 = qr/a/;
our $s2 = qr/a/;
our $s3 = qr/a/;
substr( $s1, 0, 1, $in );
substr $s2, 0, 1, $in;
my $part = substr( $s3, 0, 1 );
print "1\n" if $str =~ /\Q$s1\E\Q$s2\E/; # expect: S019 S019
print "1\n" if $str =~ /$s3/;

# The CORE:: forms of the builtins, and tie.
our $k1 = qr/a/;
our $k2 = qr/a/;
our $k3 = qr/a/;
our $k4 = qr/a/;
our $k5 = qr/a/;
our $k6 = qr/a/;
our $k7 = qr/a/;
our $k8 = qr/a/;
our $k9 = qr/a/;
CORE::chomp($k1);
CORE::chop $k2;
CORE::read( $fh, $k3, 10 );
CORE::sysread $fh, $k4, 10;
CORE::recv( $fh, $k5, 10, 0 );
CORE::open( $k6, '<', $0 ) or die;
CORE::opendir( $k7, '.' ) or die;
CORE::substr( $k8, 0, 1, $in );
tie $k9, 'main';
print "1\n" if $str =~ /\Q$k1\E\Q$k2\E\Q$k3\E\Q$k4\E\Q$k5\E\Q$k6\E\Q$k7\E\Q$k8\E\Q$k9\E/; # expect: S019 S019 S019 S019 S019 S019 S019 S019 S019

# A variable nested in parentheses or a conditional in a write position.
our $n1 = qr/a/;
our $n2 = qr/a/;
our $n3 = qr/a/;
our $n4 = qr/a/;
our $n5 = qr/a/;
our $n6 = qr/a/;
our $n7 = qr/a/;
my $z;
( $z, ($n1) ) = @ARGV;
chomp( ($n2) );
chomp +($n3);
chomp( $c ? $z : $n4 );
for my $i ( 1, ($n5) ) { $i = $in }
for ( $z, ( ( $n6 ) ) ) { }
chomp( ( $z, $n7 ) );
print "1\n" if $str =~ /\Q$n1\E\Q$n2\E\Q$n3\E\Q$n4\E\Q$n5\E\Q$n6\E\Q$n7\E/; # expect: S019 S019 S019 S019 S019 S019 S019

# The right-hand side of an assignment in the argument, and the arguments of
# a nested call, are not changed.
our $u1 = qr/a/;
our $u2 = qr/a/;
chomp( my $copy = $u1 );
chomp( ( foo $u2 ) ) if 0;
print "1\n" if $str =~ /$u1$u2/;

sub TIESCALAR { return bless {}, shift }
sub FETCH     { return 'a' }
sub foo       { return @_ }
