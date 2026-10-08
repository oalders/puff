use v5.36;
use Test2::V0;

use Puff::CLI::Command::check ();
use Time::HiRes qw( sleep );

my $progress = \&Puff::CLI::Command::check::_progress;

open my $fh, '>', \my $shown or die $!;
is( $progress->( $fh, 0 ), undef, 'no callback when not a terminal' );

my $cb = $progress->( $fh, 1 );
$cb->( 1, 3 );
is( $shown, undef, 'quiet for the first half second' );

sleep 0.6;
$cb->( 2, 3 );
is( $shown, "\rChecking 2/3 files", 'then shows done/total' );

$cb->( 3, 3 );
is( $shown, "\rChecking 2/3 files\r\e[K", 'and erases itself after the last file' );

$shown = undef;
$cb = $progress->( $fh, 1 );
$cb->( 1, 1 );
is( $shown, undef, 'a quick run never draws or erases' );

done_testing;
