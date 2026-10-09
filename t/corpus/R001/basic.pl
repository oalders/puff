use v5.36;

sub ready { return $_[0] }
sub go    { return 1 }
sub wait_ { return 0 }

unless ( ready(1) ) { # expect: R001
    wait_();
}
else {
    go();
}

unless ( ready(0) ) { wait_() } else { go() } # expect: R001

unless (ready(1)){wait_()}else{go()} # expect: R001

for my $n ( 1 .. 3 ) {
    unless ( my $odd = $n % 2 ) { # expect: R001
        # even
        say "$n is even";
    }
    else {
        # odd: $odd is in scope here too
        say "$n is odd ($odd)";
    }
}

OUTER: unless ( ready(1) ) { # expect: R001
    wait_();
}
else {
    go();
}

sub pick ($x) {
    unless ($x) { return 'no' } else { return 'yes' } # expect: R001
}

unless ( ready(1) ) { # expect: R001
    unless ( ready(0) ) { # expect: R001
        wait_();
    }
    else {
        go();
    }
}
else {
    go();
}

unless ( ready(1) ) {} else { go() } # expect: R001
