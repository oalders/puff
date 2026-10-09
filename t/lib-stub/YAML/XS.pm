package YAML::XS;

# Stand-in for t/fixed-compiles.t, so the S012 fixtures compile without the
# real (optional) module installed.

use v5.36;

our $LoadBlessed = 1;

sub import {
    my $caller = caller;
    no strict 'refs';
    *{"${caller}::$_"} = sub { }
        for qw( Load LoadFile Dump );
    return;
}

1;
