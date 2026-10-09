package Mojo::Base;

# Stand-in for t/fixed-compiles.t, so the U002 fixtures compile without the
# real (optional) module installed. Like the real one, it enables say.

use v5.36;

sub import {
    strict->import;
    warnings->import;
    feature->import('say');
    return;
}

1;
