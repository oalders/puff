use strict;
use warnings;

our $input;
my ( $name, $str, $sep, $ref, %h, @list ) = ( 'a', 'b', ',', { k => 1 }, ( k => 1 ) );
my $obj = { key => 'x', list => ['y'] };

print "1\n" if $str =~ /\Q$input\E/; # expect: S019
print "1\n" if $str =~ m/^\Q$input\E\z/; # expect: S019
print "1\n" if $str =~ m{\Q$name\E}x; # expect: S019
( my $copy = $str ) =~ s/\Q$input\E/x/g; # expect: S019
( $copy = $str ) =~ s{\Q$input\E}{$name}g; # expect: S019
my $q = qr/prefix-\Q$name\E-suffix/; # expect: S019
my @parts = split /\Q$sep\E/, $str; # expect: S019
print "1\n" if $str =~ /\Q$input\E|\Q$name\E/; # expect: S019 S019
print "1\n" if $str =~ /\Q${name}\Ex/; # expect: S019
print "1\n" if $str =~ /\Q$obj->{key}\E/; # expect: S019
print "1\n" if $str =~ /\Q$obj->{list}->[0]\E/; # expect: S019
print "1\n" if $str =~ /\Q$obj->{list}[0]\E/; # expect: S019
print "1\n" if $str =~ /\Q$h{k}\E/; # expect: S019
print "1\n" if $str =~ /\Q$h{'k'}\E/; # expect: S019
print "1\n" if $str =~ /\Q$$ref{k}\E/; # expect: S019
print "1\n" if $str =~ /\Q$ref->{k}{k}\E/; # expect: S019
print "1\n" if $str =~ /\Q$input\E\Q$name\E/; # expect: S019
print "1\n" if $str =~ /\\\Q$input\E/; # expect: S019
print "1\n" if $str =~ /a\Q$name\E$/; # expect: S019
print "1\n" if $str =~ /(\Q$input\E)/; # expect: S019
print "1\n" if $str =~ /\L\Q$input\E\E/; # expect: S019
print "1\n" if $str =~ /\Q$name\E{2}/; # expect: S019
print "1\n" if $str =~ /^\Q$main::input\E/; # expect: S019
print "1\n" if $str =~ m!\Q$input\E!; # expect: S019
print "1\n" if $str =~ m(\Q$input\E); # expect: S019
print "1\n" if $str =~ m?\Q$input\E?; # expect: S019
print "1\n" if $str =~ m#\Q$input\E#; # expect: S019
print "1\n" if $str =~ /[\Q$name\E]/; # expect: S019
print "1\n" if $str =~ /\Q$name\E \Q$input\E/x; # expect: S019 S019
print "1\n" if $str =~ /$1\Q$name\E/; # expect: S019
print "1\n" if $str =~ /\Q$ENV{HOME}\E/; # expect: S019
for (@list) {
    print "1\n" if $str =~ /\Q$_\E/; # expect: S019
}
print "1\n" if $str =~ /
    a
    \Q$input\E # expect: S019
/x;
