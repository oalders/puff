use v5.36;
use feature 'try';
no warnings 'experimental::try';

sub risky { die "no\n" }

sub one {
    try { risky() } catch ($e) { warn $e }
    return 1;
}

1;
