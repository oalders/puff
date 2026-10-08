use strict;
use warnings;

sub head {
    my ($f) = @_;
    sysopen(my $in, $f, 0) or die; # expect: S003
    binmode($in, ':raw');
    my $n = fileno $in;
    seek($in, 0, 0);
    read($in, my $buf, 10);
    my $at = tell($in);
    say {$in} 'never' if eof($in);
    close $in;
    return $buf;
}

sub tail {
    my ($f) = @_;
    open(my $log, q{>>}, "$f.log") or die;
    open(my $src, q{<}, $f) or die; # expect: S003
    my @lines = <$src>;
    close($src);
    return $lines[-1];
}
