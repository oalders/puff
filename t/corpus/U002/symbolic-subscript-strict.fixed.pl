use strict;
use feature 'say';
my $x = q{};
my %h = ( k => \$x );
my $obj = { a => \$x };
${ $h{k} } = "!";
${ $obj->{a} } = "!";
say "hello"; # expect: U002
