use strict;
use warnings;

use Encode ();

# Writes the rule does not see, as documented. They are pinned here so that
# a change in what is seen shows up. Each variable is taken to still hold
# its qr//, so none is reported.
my ( $str, $in ) = ( 'a', 'b' );

# Through @_, the $_ of map or grep, a glob or a symbolic name.
our $g1 = qr/a/;
our $g2 = qr/a/;
our $g3 = qr/a/;
our $g4 = qr/a/;
our $g5 = qr/a/;
our $g6 = qr/a/;
sub set_first { $_[0] = $in; return }
set_first($g1);
my @m = map { $_ = $in } $g2;
my @g = grep { $_ = $in } $g3;
*g4 = \$in;
{
    no strict 'refs';
    ${'main::g5'} = $in;
}
$::{g6} = \$in;
print "1\n" if $str =~ /$g1$g2$g3$g4$g5$g6/;

# A string eval and a regex code block.
our $e1 = qr/a/;
our $e2 = qr/a/;
eval '$e1 = $in; 1' or die;
{
    use re 'eval';
    $str =~ /(?{ $e2 = $in })/;
}
print "1\n" if $str =~ /$e1$e2/;

# A postfix dereference, an lvalue sub, the aliases of sort, a foreach over
# several variables at a time and a (??{ ... }) code block.
our $p1 = qr/a/;
our $p2 = qr/a/;
our $p3 = qr/a/;
our $p4 = qr/a/;
our $p5 = qr/a/;
sub lv : lvalue { $p2 }
$p1->$*++ if 0;
lv() = $in;
for ( sort $p3 ) { $_ = $in }
{
    no warnings 'experimental::for_list';
    for my ( $i, $j ) ( $p4, $in ) { $i = $in }
}
{
    use re 'eval';
    $str =~ /(??{ $p5 = $in })/;
}
print "1\n" if $str =~ /$p1$p2$p3$p4$p5/;

# The replacement of s///e, the code of "@{[ ... ]}" and "${\ ... }",
# Encode functions that change an argument and a call through `&`.
our $h1  = qr/a/;
our $h2  = qr/a/;
our $h3  = qr/a/;
our $h4  = qr/a/;
our $h5  = qr/a/;
our $h6  = qr/a/;
our $h7  = qr/a/;
our $h8  = qr/a/;
our $h9  = qr/a/;
our $h10 = qr/a/;
my $copy = $str;
$copy =~ s/a/$h1 = $in/e;
my $str1 = "@{[ $h2 = $in ]}";
my $str2 = "${\ ( $h3 = $in )}";
Encode::from_to( $h4, 'latin1', 'UTF-8' );
my $dec = Encode::decode( 'UTF-8', $h5, Encode::FB_CROAK() );
my $enc = Encode::encode( 'UTF-8', $h6, Encode::FB_CROAK() );
Encode::_utf8_on($h7);
Encode::_utf8_off($h8);
&CORE::chomp($h9) if 0;
&utf8::decode($h10);
print "1\n" if $str =~ /$h1$h2$h3$h4$h5$h6$h7$h8$h9$h10/;
