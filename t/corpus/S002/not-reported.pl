use strict;
use warnings;

my ( $obj, $x, $y, $buf );
open(my $fh, '<', 'file.txt') or die;
open my $out, '>', $x or die;
$obj->open($x, $y);
open(my $mem, '<', \$buf);
