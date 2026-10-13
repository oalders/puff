use strict 'vars';
use feature 'say';
my $x = { a => chr 92 };
${ $x->{a} } = q{};
print "x\n"; # expect: U002
