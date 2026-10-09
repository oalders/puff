use v5.36;

my ( $in, $str, @in ) = ( 'a', 'b' );

# An outer qr// does not hide an inner declaration of the same name: the
# nearest declaration visible from the use decides.
my $x = qr/x/;
my $p = qr/p/;
my $t = qr/t/;
my $u = qr/u/;
my $v = qr/v/;
sub shifted { my $x = shift; return $str =~ /^\Q$x\E/ } # expect: S019
for my $p (@in) { print "1\n" if $str =~ /\Q$p\E/ } # expect: S019
sub signature ($t) { return $str =~ /\Q$t\E/ } # expect: S019
sub list { my ($u) = @_; return $str =~ /\Q$u\E/ } # expect: S019
sub bare { my $v; return $str =~ /\Q$v\E/ } # expect: S019

# Any other write to the name means it may hold input.
our $o = qr/o/;
sub localized { local $o = $in; return $str =~ /\Q$o\E/ } # expect: S019
my $r = qr/r/;
$r .= $in;
print "1\n" if $str =~ /\Q$r\E/; # expect: S019
my $s = quotemeta $in;
$s =~ s/a/$in/;
print "1\n" if $str =~ /\Q$s\E/; # expect: S019
my $w = quotemeta $in;
$w =~ tr/a/b/;
print "1\n" if $str =~ /\Q$w\E/; # expect: S019
my $d = qr/d/;
$d ||= $in;
print "1\n" if $str =~ /\Q$d\E/; # expect: S019

# An assignment inside a condition is not seen.
if ( ( my $c = qr/c/ ) ) { print "1\n" if $str =~ /\Q$c\E/ } # expect: S019

# A file-scope qr// used in a sub that does not redeclare it is skipped.
my $delim = qr/,/;
sub splits { return $str =~ /$delim/ }
