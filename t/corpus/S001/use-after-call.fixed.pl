use Crypt::PRNG qw(rand);
my $x = rand(2); # expect: S001
use warnings;
my $y = rand(3); # expect: S001
