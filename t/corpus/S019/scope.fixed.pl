use strict;
use warnings;

my ( %opt, $args, $input, $str );
our $later;

# A same-named variable assigned a qr// in another sub does not count.
sub build {
    my $token = qr/\w+/;
    return $token;
}

sub match {
    my ($token) = @_;
    return $str =~ /\Q$token\E/; # expect: S019
}

# A qr// or quotemeta is only one possible value of the right-hand side.
my $sep = $opt{sep} // qr/,/;
my $q = $args->{q} || quotemeta $input;
my $either = $input ? qr/a/ : $input;
my $joined = join '|', map {quotemeta} @ARGV;
print "1\n" if $str =~ /\Q$sep\E\Q$q\E/; # expect: S019 S019
print "1\n" if $str =~ /\Q$either\E\Q$joined\E/; # expect: S019 S019

# //= and ||= keep a value that may be input.
our $maybe;
$maybe //= qr/x/;
print "1\n" if $str =~ /\Q$maybe\E/; # expect: S019

# The assignment comes after the use.
print "1\n" if $str =~ /\Q$later\E/; # expect: S019
$later = qr/x/;

# Assigned in a block that does not enclose the use.
if ($input) {
    my $inner = qr/x/;
}
my $inner = $input;
print "1\n" if $str =~ /\Q$inner\E/; # expect: S019
