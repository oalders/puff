package namespace::autoclean;

# Stand-in for t/fixed-compiles.t, so the M fixtures compile without the
# real (optional) module installed.

use v5.36;

sub import {return}

1;
