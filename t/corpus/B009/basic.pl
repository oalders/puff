use v5.36;

my ( $name, $count, $fh, $x, $y, %h, @list );
my $s = sprintf '%s: %d', $name; # expect: B009
printf "%s\n", $x, $y; # expect: B009
$s = sprintf( '%s', $x, $y ); # expect: B009
$s = sprintf('%s %s'); # expect: B009
$s = sprintf q{%d items}, $count, 1; # expect: B009
$s = sprintf qq{%s\t%s\n}, $x; # expect: B009
$s = CORE::sprintf '%s', 1, 2; # expect: B009
printf STDERR '%s %s', $x; # expect: B009
printf {$fh} '%s', $x, $y; # expect: B009
printf $fh '%s %s', $x; # expect: B009
printf( STDERR '%d', 1, 2 ); # expect: B009
$s = sprintf '%*d', $x; # expect: B009
$s = sprintf '%.*f', 2, 3.14159, 1; # expect: B009
$s = sprintf '%-*.*s', 5, 2; # expect: B009
$s = sprintf '%*vd', '1.2.3'; # expect: B009
$s = sprintf '%vd %s', '1.2.3'; # expect: B009
$s = sprintf '100%% %s'; # expect: B009
$s = sprintf '%s', $h{a}, $x->[0]{b}; # expect: B009
$s = sprintf '%s', $x . 'y', $$x; # expect: B009
$s = sprintf '%d', scalar(@list), scalar @list; # expect: B009
$s = sprintf '%s', $x ? $y : 'z', $#list; # expect: B009
$s = sprintf "%s\n"; # expect: B009
$s = sprintf "%s %s", # expect: B009
    $x;
my @out = ( sprintf( '%s', $x, $y ), 1 ); # expect: B009
$s = sprintf '%05.2f %x %#o %e %g %c %b %u %i %hd %ld %lld %qd', 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11; # expect: B009
printf sprintf '%s %s', $x; # expect: B009
$s = sprintf '%s', $count ? sprintf( '%s %s', $x ) : 'n'; # expect: B009
$s = sprintf '%vD', '1.2.3', $x; # expect: B009
