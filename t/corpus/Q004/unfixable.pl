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
