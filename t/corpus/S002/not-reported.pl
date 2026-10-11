use strict;
use warnings;

my ( $obj, $x, $y, $buf );
open(my $fh, '<', 'file.txt') or die;
open my $out, '>', $x or die;
$obj->open($x, $y);
open(my $mem, '<', \$buf);
my $kid = open( my $from_kid, '-|' );
my $to_kid = open my $to, "|-";
# Leading ASCII space is trimmed, so this still forks (_is_fork_open).
my $kid2 = open( my $from_kid2, " -|" );
