use strict;
use warnings;

sub head {
    my ($f) = @_;
    sysopen(IN, $f, 0) or die; # expect: S003
    binmode(IN, ':raw');
    my $n = fileno IN;
    seek(IN, 0, 0);
    read(IN, my $buf, 10);
    my $at = tell(IN);
    say {IN} 'never' if eof(IN);
    close IN;
    return $buf;
}

sub tail {
    my ($f) = @_;
    open(my $log, q{>>}, "$f.log") or die;
    open(SRC, q{<}, $f) or die; # expect: S003
    my @lines = <SRC>;
    close(SRC);
    return $lines[-1];
}
