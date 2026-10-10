package Try::Tiny;

# Stand-in for t/fixed-compiles.t, so the B005 fixtures compile without the
# real (optional) module installed. The prototypes match Try::Tiny's, so the
# fixtures parse the same way.

use v5.36;

sub try     : prototype(&;@) {return}
sub catch   : prototype(&;@) {return}
sub finally : prototype(&;@) {return}

sub import {
    my $caller = caller;
    no strict 'refs';
    *{"${caller}::$_"} = \&{$_} for qw( try catch finally );
    return;
}

1;
