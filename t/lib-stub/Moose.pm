package Moose;

# Stand-in for t/fixed-compiles.t, so the M fixtures compile without the
# real (optional) module installed.

use v5.36;

sub import {
    my $caller = caller;
    no strict 'refs';
    *{"${caller}::$_"} = sub { }
        for qw( has extends with before after around );
    return;
}

1;
