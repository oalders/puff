use strict;
use warnings;

my ( $f, $obj );

if (open(CONDFH, '<', $f)) { # expect: S003
    close CONDFH;
}

sub opener { open(SHARED, '<', $f) or die } # expect: S003
sub reader { my @l = <SHARED>; close SHARED }

open(TWICE, '<', $f); # expect: S003
close TWICE;
open(TWICE, '>', $f); # expect: S003
close TWICE;

open(GLOBBED, '<', $f); # expect: S003
my $copy = \*GLOBBED;
close GLOBBED;

open(PASSED, '<', $f); # expect: S003
consume(PASSED);
close PASSED;

open(SELECTED, '>', $f); # expect: S003
my $old = select(SELECTED);
close SELECTED;

my $ok = open(ASSIGNED, '<', $f); # expect: S003
close ASSIGNED;

close EARLY;
open(EARLY, '<', $f); # expect: S003

{
    open(INNER, '<', $f); # expect: S003
}
close INNER;

{
    open(NESTED, '<', $f); # expect: S003
    sub closer { close NESTED }
}

open(EVALED, '<', $f); # expect: S003
eval 'close EVALED';

open(QUALIFIED, '<', $f); # expect: S003
close main::QUALIFIED;

open(PARENS, '>', $f); # expect: S003
print(PARENS "x\n");

open(FATCOMMA, '>', $f); # expect: S003
print FATCOMMA => 1;

open(TESTED, '<', $f); # expect: S003
my $empty = -z TESTED;

open(FMT, '>', $f); # expect: S003
write(FMT);

open(Pkg::HANDLE, '<', $f); # expect: S003
close Pkg::HANDLE;

socket(SOCK, 1, 1, 0); # expect: S003
close SOCK;

open(OTHERPKG, '<', $f); # expect: S003
package Other;
close OTHERPKG;
