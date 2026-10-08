package Local::Base;
sub new { return bless {}, shift }

package Local::Mixed;
use base qw( Local::Base Exporter ); # expect: U001

package Local::Var;
my $class;
BEGIN { $class = 'Exporter' }
use base $class; # expect: U001

package Local::Tie;
use base 'Tie::StdArray'; # expect: U001

1;
