package Local::Base;
sub new { return bless {}, shift }

package Local::Other;
sub other { return 1 }

package Local::Child;
use parent -norequire, 'Local::Base'; # expect: U001

package Local::Both;
use parent -norequire, qw( Local::Base Local::Other ); # expect: U001

package Local::Paren;
use parent ( -norequire, "Local::Base" ); # expect: U001

package My::Exporter;
use parent 'Exporter'; # expect: U001

package My::Two;
use parent qw( Exporter Tie::Hash ); # expect: U001

package My::Hash;
use Tie::Hash;
use parent -norequire, qw( Tie::StdHash ); # expect: U001

1;
