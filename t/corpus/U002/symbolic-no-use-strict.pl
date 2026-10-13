use feature 'say';
my %h = ( k => chr 92 );
${ $h{k} } = q{};
print "x\n"; # expect: U002
