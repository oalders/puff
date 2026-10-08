package Local::Base;
sub new { return bless {}, shift }

package Local::Other;
sub other { return 1 }

package Local::Child;
use base 'Local::Base'; # expect: U001

package Local::Both;
use base qw( Local::Base Local::Other ); # expect: U001

package Local::Paren;
use base ( "Local::Base" ); # expect: U001

package My::Exporter;
use base 'Exporter'; # expect: U001

package My::Two;
use base qw( Exporter Tie::Hash ); # expect: U001

package My::Hash;
use Tie::Hash;
use base qw( Tie::StdHash ); # expect: U001

1;
