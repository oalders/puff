use strict;
use warnings;

my %h = ( 'two words' => 1, '01' => 2, '1' => 3, 'a-b' => 4, 'Foo::Bar' => 5, '' => 6 );
my @pair = @h{ 'two words', '01' };
my @both = @h{'a', 'b'};
print $h{'two words'}, $h{'01'}, $h{'a-b'}, $h{''};
my %ops = ( 'q' => 1, 'qq' => 2, 'qw' => 3, 'qx' => 4, 'm' => 5, 's' => 6, 'tr' => 7, 'y' => 8, 'x' => 9 );
print $ops{'s'}, $ops{'y'}, $ops{'x'};
my %pkg = ( '__PACKAGE__' => 1 );
print $pkg{'__PACKAGE__'};
my $k = 'name';
print $h{"$k"}, $h{ 'na' . 'me' }, $h{ lc 'NAME' };
my @list = ( 'name', 1 );
print 'name' . 'x', "\n";
my $sym = ${'main::x'} // ''; ## no critic
my %u = ( 'café' => 1 );
my %v = ( 'v2' => 1 );
print $v{'v2'};
