use strict;
use warnings;

my ( $file, $dir, $f, $g );
open(FH, "<$file"); # expect: S002
open(my $fh, ">$dir/out.txt") or die; # expect: S002
open(LOG, '>>log.txt'); # expect: S002
open FH, "+< $f" or die; # expect: S002
open(FH, $file); # expect: S002
open(FH, "data.txt"); # expect: S002
open(FH, '<$f'); # expect: S002
# In a '...' string, "-$x" is a literal name, not a variable.
open(FH, '-$x'); # expect: S002
open(FH, '>-$x'); # expect: S002
open(FH, "<$f$g"); # expect: S002
open(FH, "<$f "); # expect: S002
