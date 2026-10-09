use strict;
use warnings;

our $input;
my ( $name, $str, $sep, $ref, %h, @list ) = ( 'a', 'b', ',', { k => 1 }, ( k => 1 ) );
my $obj = { key => 'x', list => ['y'] };

print "1\n" if $str =~ /$input/; # expect: S019
print "1\n" if $str =~ m/^$input\z/; # expect: S019
print "1\n" if $str =~ m{$name}x; # expect: S019
( my $copy = $str ) =~ s/$input/x/g; # expect: S019
( $copy = $str ) =~ s{$input}{$name}g; # expect: S019
my $q = qr/prefix-$name-suffix/; # expect: S019
my @parts = split /$sep/, $str; # expect: S019
print "1\n" if $str =~ /$input|$name/; # expect: S019 S019
print "1\n" if $str =~ /${name}x/; # expect: S019
print "1\n" if $str =~ /$obj->{key}/; # expect: S019
print "1\n" if $str =~ /$obj->{list}->[0]/; # expect: S019
print "1\n" if $str =~ /$obj->{list}[0]/; # expect: S019
print "1\n" if $str =~ /$h{k}/; # expect: S019
print "1\n" if $str =~ /$h{'k'}/; # expect: S019
print "1\n" if $str =~ /$$ref{k}/; # expect: S019
print "1\n" if $str =~ /$ref->{k}{k}/; # expect: S019
print "1\n" if $str =~ /\Q$input\E$name/; # expect: S019
print "1\n" if $str =~ /\\$input/; # expect: S019
print "1\n" if $str =~ /a$name$/; # expect: S019
print "1\n" if $str =~ /($input)/; # expect: S019
print "1\n" if $str =~ /\L$input\E/; # expect: S019
print "1\n" if $str =~ /$name{2}/; # expect: S019
print "1\n" if $str =~ /^$main::input/; # expect: S019
print "1\n" if $str =~ m!$input!; # expect: S019
print "1\n" if $str =~ m($input); # expect: S019
print "1\n" if $str =~ m?$input?; # expect: S019
print "1\n" if $str =~ m#$input#; # expect: S019
print "1\n" if $str =~ /[$name]/; # expect: S019
print "1\n" if $str =~ /$name $input/x; # expect: S019 S019
print "1\n" if $str =~ /$1$name/; # expect: S019
print "1\n" if $str =~ /$ENV{HOME}/; # expect: S019
for (@list) {
    print "1\n" if $str =~ /$_/; # expect: S019
}
print "1\n" if $str =~ /
    a
    $input # expect: S019
/x;
