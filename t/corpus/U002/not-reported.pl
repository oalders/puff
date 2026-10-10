use v5.36;

my ( $fh, $x, $y ) = ( \*STDOUT, 1, 'z' );
print 'no newline';
print 'single\n';
print "no newline";
print "escaped \\n";
print "escaped \\\\\\n" if 0;
print $x, "\n";
print "x\n", $y;
print "a\n" x 3;
print $x ? "y\n" : "n\n";
print "\Q$y\n";
print "\x0a";
print <<"END";
heredoc
END
$fh->print("method\n");
my %h = ( print => "hash\n" );
CORE::print "core\n";
print length "x\n";
print;
printf "%s\n", $x;
print "a$\n";
print "$\n";
print "a $\n";
print qq{cost: 5$\n};
print "a\\$\n";
print "a\$$\n";
print "$$$\n";
print qq n a\nn;
