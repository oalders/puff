package Math::Random::Secure;

# Stand-in for t/fixed-compiles.t, so the S001 fixtures compile without the
# real (optional) module installed.

use v5.36;

use Exporter qw( import );

our @EXPORT_OK = qw( rand srand irand );

sub rand  { CORE::rand(@_) }
sub srand { CORE::srand(@_) }
sub irand { int CORE::rand( 2**32 ) }

1;
