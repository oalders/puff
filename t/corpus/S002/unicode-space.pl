use strict;
use warnings;
use utf8;

open(FH, ">x "); # expect: S002
open(FH, "<  x"); # expect: S002
open(FH, ' >x'); # expect: S002
open(FH, "x "); # expect: S002
open(FH, ">x "); # expect: S002
open(FH, "<  x"); # expect: S002
open(FH, ' >x'); # expect: S002
open(FH, "x "); # expect: S002
open(FH, ">x"); # expect: S002
open(FH, "< x"); # expect: S002
open(FH, '>x'); # expect: S002
open(FH, "x"); # expect: S002
open(FH, ">x \t"); # expect: S002
open(FH, '>x '); # expect: S002
open(FH, " -|"); # expect: S002
