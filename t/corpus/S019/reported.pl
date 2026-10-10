use strict;
use warnings;

our $input;
my ( $name, $str, $sep, $ref, %h, @list ) = ( 'a', 'b', ',', { k => 1 }, ( k => 1 ) );
my $obj = { key => 'x', list => ['y'] };
my ( $args, %params, %opt, $self, $Input, $Query );

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
print "1\n" if $str =~ /^$main::input/; # expect: S019
print "1\n" if $str =~ m!$input!; # expect: S019
print "1\n" if $str =~ m($input); # expect: S019
print "1\n" if $str =~ m?$input?; # expect: S019
print "1\n" if $str =~ m#$input#; # expect: S019
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

# ${x} ends the variable: what follows is pattern text.
print "1\n" if $str =~ /${name}{k}/; # expect: S019
print "1\n" if $str =~ /${name}->[0]/; # expect: S019
print "1\n" if $str =~ /${name}[abc]/; # expect: S019

# Hash keys and capitalised names that are not all caps.
print "1\n" if $str =~ /$args->{pattern}/; # expect: S019
print "1\n" if $str =~ /$params{regex}/; # expect: S019
print "1\n" if $str =~ /$opt{re}/; # expect: S019
print "1\n" if $str =~ /$self->{config}{regex}/; # expect: S019
print "1\n" if $str =~ /$Input|$Query/; # expect: S019 S019
print "1\n" if $str =~ /$Pkg::Const/; # expect: S019
print "1\n" if $str =~ /a # a comment ends at the newline
    $name # expect: S019
/x;
print "1\n" if $str =~ /a # a comment ending in a backslash \
    $input/x; # expect: S019

# A \L, \U or \F replaces an active one and ends any \Q after it, so the
# second \E here ends the outer \Q.
print "1\n" if $str =~ /\Qa\Ub\Lc\E\E$input/; # expect: S019
print "1\n" if $str =~ /\Qa\Fb\Uc\E\E$input/; # expect: S019
print "1\n" if $str =~ /\Ua\Qb\Lc\E$input/; # expect: S019
