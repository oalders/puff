package Local::Base;
sub new { return bless {}, shift }

package Local::Child;
use parent -norequire, 'Local::Base';

package My::Exporter;
use parent 'Exporter';
no base;
require base;
my %base = ( base => 1 );

1;
