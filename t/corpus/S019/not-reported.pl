use strict;
use warnings;

my ( $input, $str, $copy, %opt, @words ) = ( 'a', 'b', 'c' );
my $self = { pattern => 'x', config => { regex => 'y' } };

# Already quoted.
print "1\n" if $str =~ /\Q$input\E/;
print "1\n" if $str =~ /^\Q$input/;
print "1\n" if $str =~ /\Q\L$input\E$str\E/;

# Escaped sigils, anchors and punctuation variables.
print "1\n" if $str =~ /\$input/;
print "1\n" if $str =~ /foo$/;
print "1\n" if $str =~ /(foo$)/;
print "1\n" if $str =~ /foo$|bar/;
print "1\n" if $str =~ /foo$ # end
    /x;
print "1\n" if $str =~ /^(a)$1\z/;
print "1\n" if $str =~ /$&/;
print "1\n" if $str =~ /[$]/;
print "1\n" if $str =~ /${^MATCH}/p;
print "1\n" if $str =~ /a$#words/;

# Patterns that do not interpolate, and the replacement side of s///.
print "1\n" if $str =~ m'$input';
( $copy = $str ) =~ s'$input'x';
( $copy = $str ) =~ s/x/$input/;
( $copy = $str ) =~ s{x}{$input}e;

# Names that say they hold a pattern.
my ( $re, $rx, $regex, $regexp, $pattern, $pat, $pats, $word_re, $re_word, $word_rx, $alt_regexes, $fooRegex, $filePattern );
print "1\n" if $str =~ /$re|$rx|$regex|$regexp|$pattern|$pat|$pats/;
print "1\n" if $str =~ /$word_re|$re_word|$word_rx|$alt_regexes|$fooRegex|$filePattern/;

# Assigned only a qr// or quotemeta, earlier in this or an enclosing block.
my $word = qr/\w+/;
my $quoted = quotemeta $input;
our $called = quotemeta( $self->{config}{regex} );
my $key = quotemeta $self->{config}->{regex};
my $either = qr/(?:a|b)/i;
print "1\n" if $str =~ /^$word$quoted$called$key$either/;
for my $item (@words) {
    my $inner = qr/\Q$item\E/;
    if ($item) {
        print "1\n" if $str =~ /$word$inner/;
    }
}
sub uses_outer { return $_[0] =~ /$word/ }

# Arrays and code blocks.
print "1\n" if $str =~ /@words/;
print "1\n" if $str =~ /@{[ $input ]}/;
print "1\n" if $str =~ /(?{ $input })/;

# Not a regex token.
print "1\n" if $str =~ $input;
my @parts = split $input, $str;

# An all-caps scalar is taken to be a constant.
our ( $WS, $Foo::CRLF, $X1_Y ) = ( ' ', "\r\n", 'x' );
print "1\n" if $str =~ /^$WS*$Foo::CRLF$X1_Y/;
