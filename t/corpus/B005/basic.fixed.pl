use strict;
use warnings;
use Try::Tiny;

sub risky   { die "no\n" }
sub cleanup { return 1 }

sub one {
    try { risky() } catch { warn $_ }; # expect: B005
    return cleanup();
}

sub two {
    try { risky() } # expect: B005
    finally { cleanup() };
    my $x = 2;
    return $x;
}

sub three {
    try { risky() } catch { warn $_ } finally { cleanup() }; # expect: B005
    grep { $_ } ();
    return;
}

1;
