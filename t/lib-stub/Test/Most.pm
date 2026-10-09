package Test::Most;

# Stand-in for t/fixed-compiles.t, so the T001 fixtures compile without the
# real (optional) module installed.

use v5.36;

use Test::More ();

sub import {
    my $caller = caller;
    no strict 'refs';
    *{"${caller}::$_"} = \&{"Test::More::$_"}
        for qw( ok is isnt );
    return;
}

1;
