use strict;
use warnings;

my ( $f, $d, $fh, $obj );
open(STDOUT, '>', $f);
open(STDERR, '>>', $f);
open(STDIN, '<', $f);
open(my $in, '<', $f);
open($fh, '<', $f);
open my $out, '>', $f or die;
opendir(my $dh, $d);
$obj->open(FH, '<', $f);
open(local *FH, '<', $f);
