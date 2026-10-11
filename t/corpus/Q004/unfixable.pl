use strict;
use warnings;

sub foo { return @_ }
sub print { return 1 }
sub open { return 1 }

&foo; # expect: Q004
my $x = &foo; # expect: Q004
sub wrap { &foo } # expect: Q004
return &foo if 0; # expect: Q004
my $r = &foo->(1); # expect: Q004
&print(1); # expect: Q004
&open( my $fh, '<', 'x' ); # expect: Q004
print &foo (1); # expect: Q004
sub any { return 1 }
sub all { return 1 }
&any(1); # expect: Q004
&all(1); # expect: Q004
sub isa    { return 1 }
sub class  { return 1 }
sub method { return 1 }
sub field  { return 1 }
sub ADJUST { return 1 }
&isa(1); # expect: Q004
&class(1); # expect: Q004
&method(1); # expect: Q004
&field(1); # expect: Q004
&ADJUST(1); # expect: Q004
sub qx { return 1 }
sub __CLASS__ { return 1 }
&qx(1); # expect: Q004
&__CLASS__(1); # expect: Q004
