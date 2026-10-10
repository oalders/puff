use strict;
use warnings;

my $count = 010; # expect: B003
my $neg = -0644; # expect: B003
my $under = 0_755; # expect: B003
my @list = ( 1, 02, 3 ); # expect: B003
my %h = ( 007 => 'bond' ); # expect: B003
my $mode = 0755; # expect: B003
print 0755 + 1, "\n"; # expect: B003
my $sum = $count + 01; # expect: B003
my $x = foo(0600); # expect: B003
$h{0644} = 1; # expect: B003
sprintf '%04o', 0755 if 0; # expect: B003
my $obj = bless {}, 'X';
$obj->chmod( 0755, 1 ) if 0; # expect: B003
$obj->mkdir( { size => 0755 } ) if 0; # expect: B003
mkdir 0755 if 0; # expect: B003
chmod $count, 0755 if 0; # expect: B003

sub foo { return shift }
