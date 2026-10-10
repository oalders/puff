use strict;
use warnings;

my $count = oct('010'); # expect: B003
my $neg = -oct('0644'); # expect: B003
my $under = oct('0_755'); # expect: B003
my @list = ( 1, oct('02'), 3 ); # expect: B003
my %h = ( oct('007') => 'bond' ); # expect: B003
my $mode = oct('0755'); # expect: B003
print oct('0755') + 1, "\n"; # expect: B003
my $sum = $count + oct('01'); # expect: B003
my $x = foo(oct('0600')); # expect: B003
$h{oct('0644')} = 1; # expect: B003
sprintf '%04o', oct('0755') if 0; # expect: B003
my $obj = bless {}, 'X';
$obj->chmod( oct('0755'), 1 ) if 0; # expect: B003
$obj->mkdir( { size => oct('0755') } ) if 0; # expect: B003
mkdir oct('0755') if 0; # expect: B003
chmod $count, oct('0755') if 0; # expect: B003

sub foo { return shift }
