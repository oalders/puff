use v5.36;

sub ready { return $_[0] }
sub go    { return 1 }

unless ( ready(1) ) { # expect: R001
    go();
}
elsif ( ready(2) ) {
    go();
}
else {
    go();
}

unless ( ready(1) ) { go() } # expect: R001
elsif ( ready(2) ) { go() }
elsif ( ready(3) ) { go() }
else { go() }

unless ( ready(1) ) { # expect: R001
    go();
} # not ready
else {
    go();
}

unless ( ready(1) ) { go() } else # expect: R001
# ready
{
    go();
}

unless ( ready(1) ) { # expect: R001
    print <<"END";
not ready
END
}
else {
    go();
}

unless ( ready(1) ) { print <<"END" } else { go() } # expect: R001
not ready
END
