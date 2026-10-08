use strict;
use warnings;

my ( $f, $v );

open(BARE, '>', $f); # expect: S003
print BARE;

open(SAYS, '>', $f); # expect: S003
say SAYS;

open(MODIF, '>', $f); # expect: S003
print MODIF if $v;

open(UNLESSED, '>', $f); # expect: S003
print UNLESSED unless $v;

open(BLOCKED, '>', $f); # expect: S003
{ print BLOCKED }

open(PRINTFED, '>', $f); # expect: S003
printf PRINTFED;
