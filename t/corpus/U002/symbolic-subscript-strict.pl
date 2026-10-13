use strict;
use feature 'say';
my $x = q{};
my %h = ( k => \$x );
my $obj = { a => \$x };
${ $h{k} } = "!";
${ $obj->{a} } = "!";
print "hello\n"; # expect: U002
