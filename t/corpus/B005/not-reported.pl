use strict;
use warnings;
use Try::Tiny;

sub risky { die "no\n" }

sub one {
    try { risky() } catch { warn $_ };
    return 1;
}

sub last_statement {
    try { risky() } catch { warn $_ }
}

sub value {
    my $ok = try { risky(); 1 } catch { 0 };
    return $ok;
}

sub modifier {
    my ($x) = @_;
    try { risky() } catch { warn $_ } if $x;
    return;
}

sub in_list {
    my @r = ( try { 1 } catch { 0 }, 2 );
    return @r;
}

sub or_die {
    try { 1 } catch { 0 } or die "failed\n";
    return;
}

sub method {
    my ($obj) = @_;
    $obj->try( sub {1} ) if 0;
    return;
}

1;
