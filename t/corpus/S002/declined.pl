use strict;
use warnings;

my ( $mode, $f, $h );
open(P, "ls |"); # expect: S002
open(P, "| cat"); # expect: S002
open(D, ">&STDOUT"); # expect: S002
open(X, "-"); # expect: S002
open(X, "$mode$f"); # expect: S002
open(X, ">" . $f); # expect: S002
open(X, $h->{f}); # expect: S002
open(X, qq{<$f}); # expect: S002
open(X, " file "); # expect: S002
open(FH, "\t>$f"); # expect: S002
open(FH, "<$f\n"); # expect: S002
open(FH, "< \t$f"); # expect: S002
open(FH, ">"); # expect: S002
open(FH, "<"); # expect: S002
open(FH, "<$f\x20"); # expect: S002
open(FH, "<$f\040"); # expect: S002
open(FH, "<x\x{20}"); # expect: S002
open(FH, "<$f\o{40}"); # expect: S002
open(FH, "\x20<$f"); # expect: S002
open(FH, "\x{20}$f"); # expect: S002
