use strict;
use warnings;
use feature 'bitwise';

use constant LEN => 1;

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

# A word in an argument: a constant or a unary operator is one term, and
# the arguments are counted by their commas.
our $w1 = qr/a/;
our $w2 = qr/a/;
our $w3 = qr/a/;
our $w4 = qr/a/;
our $w5 = qr/a/;
our $w6 = qr/a/;
our $w7 = qr/a/;
our $w8 = qr/a/;
my @l = (1);
substr( $w1, 0, length $in, $in );
substr( $w2, 0, LEN - 1, $in );
substr( $w3, 0, scalar @l, $in );
substr( $w4, do { 1 }, 1, $in );
chomp( defined $z ? $z : $w5 );
chomp( LEN ? $z : $w6 );
chomp( ( my $q = $in, $w7 ) );
chomp( substr( $w8, 0, 1 ) );
print "1\n" if $str =~ /\Q$w1\E\Q$w2\E\Q$w3\E\Q$w4\E\Q$w5\E\Q$w6\E\Q$w7\E\Q$w8\E/; # expect: S019 S019 S019 S019 S019 S019 S019 S019

# A conditional or parentheses as an lvalue.
our $t1 = qr/a/;
our $t2 = qr/a/;
our $t3 = qr/a/;
our $t4 = qr/a/;
our $t5 = qr/a/;
our $t6 = qr/a/;
our $t7 = qr/a/;
our $t8 = qr/a/;
our $t9 = qr/a/;
our $y;
( $c ? $y : $t1 ) = 1;
( $c ? $y : $t2 ) =~ s/a/b/;
for ( $c ? $y : $t3 ) { }
my $ref = \( $c ? $y : $t4 );
local ( $c ? $y : $t5 );
++( $c ? $y : $t6 );
($t7)++;
++($t8);
--( ($t9) );
print "1\n" if $str =~ /\Q$t1\E\Q$t2\E\Q$t3\E\Q$t4\E\Q$t5\E\Q$t6\E\Q$t7\E\Q$t8\E\Q$t9\E/; # expect: S019 S019 S019 S019 S019 S019 S019 S019 S019

# The string bitwise assignments, and more builtins that write.
our $b1  = qr/a/;
our $b2  = qr/a/;
our $b3  = qr/a/;
our $b4  = qr/a/;
our $b5  = qr/a/;
our $b6  = qr/a/;
our $b7  = qr/a/;
our $b8  = qr/a/;
our $b9  = qr/a/;
our $b10 = qr/a/;
our $b11 = qr/a/;
our $b12 = qr/a/;
our $b13 = qr/a/;
$b1 &.= $in;
$b2 |.= $in;
$b3 ^.= $in;
undef $b4;
sysopen( $b5, $0, 0 ) or die;
pipe( my $rd, $b6 ) or die;
fcntl( $fh, 1, $b7 ) if 0;
ioctl( $fh, 1, $b8 ) if 0;
shmread( 1, $b9, 0, 1 ) if 0;
msgrcv( 1, $b10, 1, 0, 0 ) if 0;
select( $b11, undef, undef, 0 );
utf8::encode($b12);
socket( $b13, 1, 1, 0 ) if 0;
print "1\n" if $str =~ /\Q$b1\E\Q$b2\E\Q$b3\E\Q$b4\E\Q$b5\E\Q$b6\E\Q$b7\E\Q$b8\E\Q$b9\E\Q$b10\E\Q$b11\E\Q$b12\E\Q$b13\E/; # expect: S019 S019 S019 S019 S019 S019 S019 S019 S019 S019 S019 S019 S019

# The right-hand side of an assignment in the argument, the arguments of a
# nested call or a method, and a 3-argument CORE::substr are not changed.
our $u1 = qr/a/;
our $u2 = qr/a/;
our $u3 = qr/a/;
our $u4 = qr/a/;
our $u5 = qr/a/;
my $o = 'main';
chomp( my $copy = $u1 );
chomp( ( foo $u2 ) ) if 0;    # parse only: foo is defined below
my $piece = CORE::substr( $u3, 0, 1 );
$o->tie($u4) if 0;
chomp $o->foo($u5) if 0;
print "1\n" if $str =~ /$u1$u2$u3$u4$u5/;

sub TIESCALAR { return bless {}, shift }
sub FETCH     { return 'a' }
sub foo       { return @_ }
