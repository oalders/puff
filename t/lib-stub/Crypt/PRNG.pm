package Crypt::PRNG;

# Stand-in for t/fixed-compiles.t, so the S001 fixtures compile without the
# real (optional) module installed.

use v5.36;

use Exporter qw( import );

our @EXPORT_OK   = qw( rand irand random_bytes );
our %EXPORT_TAGS = ( all => \@EXPORT_OK );

sub rand : prototype(;$) { CORE::rand( @_ ? $_[0] : 1 ) }
sub irand                { int CORE::rand( 2**32 ) }
sub random_bytes ($n)    { join q{}, map { chr int CORE::rand 256 } 1 .. $n }

1;
