use strict;
use warnings;

my $drink = 'coffee'; # expect: Q001
my %h = ( 'key' => '', 'single' => 1 ); # expect: Q001 Q001
print $h{'key'}, "\n"; # expect: Q001
print 'two words, punctuation!? é'; # expect: Q001
print qq{already qq}, q{already q}, 'already single';
