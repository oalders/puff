use v5.36;

my $fh = \*STDOUT;
my $x  = 1;
print "hello\n"; # expect: U002
print $fh "x: $x\n"; # expect: U002
print {$fh} "braces\n"; # expect: U002
print STDERR "to stderr\n"; # expect: U002
print("parens\n"); # expect: U002
print qq{qq string\n}; # expect: U002
print qq {spaced\n}; # expect: U002
print "a", "b\n"; # expect: U002
print "\n"; # expect: U002
print "two\n\n"; # expect: U002
print "even \\\\\n"; # expect: U002
print "modifier\n" if $x; # expect: U002
print "or\n" or die; # expect: U002
print "a\$\n"; # expect: U002
