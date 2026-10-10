use v5.36;

sub ready { return $_[0] }
sub go    { return 1 }
sub wait_ { return 0 }

if ( ready(1) ) {
    go();
}
else { # expect: R001
    wait_();
}

if ( ready(0) ) { go() } else { wait_() } # expect: R001

if (ready(1)){go()}else{wait_()} # expect: R001

for my $n ( 1 .. 3 ) {
    if ( my $odd = $n % 2 ) {
        # odd: $odd is in scope here too
        say "$n is odd ($odd)";
    }
    else { # expect: R001
        # even
        say "$n is even";
    }
}

OUTER: if ( ready(1) ) {
    go();
}
else { # expect: R001
    wait_();
}

sub pick ($x) {
    if ($x) { return 'yes' } else { return 'no' } # expect: R001
}

if ( ready(1) ) {
    go();
}
else { # expect: R001
    if ( ready(0) ) {
        go();
    }
    else { # expect: R001
        wait_();
    }
}

if ( ready(1) ) { go() } else {} # expect: R001

if ( my $v = ready(1) ) { go($v) } else { wait_() } # expect: R001
