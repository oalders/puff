# Lines here contain invisible literal characters: U+00A0 (NO-BREAK SPACE),
# U+2028 (LINE SEPARATOR), U+0085 (NEXT LINE), and ASCII \x0B and \f.
use strict;
use warnings;
use utf8;

my ( $x, @x );

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
# U+00A0 before -| is part of the mode, so this is not a fork open
# (_is_fork_open); it is reported but not fixed.
open(FH, " -|"); # expect: S002
open(FH, "x\t "); # expect: S002
open(FH, " $x"); # expect: S002
open(FH, " @x"); # expect: S002
open(FH, " \tfoo"); # expect: S002
# "-" next to U+00A0 is part of the name, not STDIN.
open(FH, "<- "); # expect: S002
open(FH, " -"); # expect: S002
# Literal \x0B is trimmed after a mode; literal \f with no mode is declined.
open(FH, ">x"); # expect: S002
open(FH, "x"); # expect: S002
