use strict;
use warnings;

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
