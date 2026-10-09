use v5.36;
use Test2::V0;

use Puff::CLI::Command::check ();
use Time::HiRes qw( time );

my $progress = \&Puff::CLI::Command::check::_progress;

# Burns CPU instead of sleeping, as a slow file would; the SIGALRM timer
# would cut a sleep short.
sub busy ($seconds) {
    my $until = time + $seconds;
    1 while time < $until;
}

local $ENV{LC_ALL} = 'C';
open my $fh, '>', \my $shown or die $!;
is( $progress->( $fh, 0 ), undef, 'no callback when not a terminal' );

my $cb = $progress->( $fh, 1 );
busy(0.3);
is( $shown, undef, 'quiet for the first half second' );
busy(0.35);
like( $shown, qr{\r[|/\\-] Finding files\e\[K\z}, 'then a spinner while finding files' );

$cb->( 0, 3 );
busy(0.25);
like( $shown, qr{\r[|/\\-] Checking 0/3 files\e\[K\z}, 'redraws on its own while a file is being checked' );
my @frames = $shown =~ m{\r([|/\\-]) }g;
cmp_ok( scalar @frames, '>=', 3, 'the spinner turns' );

$cb->( 3, 3 );
like( $shown, qr{\r\e\[K\z}, 'erases itself after the last file' );
my $final = $shown;
busy(0.25);
is( $shown, $final, 'and stops' );

$shown = undef;
$cb    = $progress->( $fh, 1 );
$cb->( 0, 0 );
busy(0.6);
is( $shown, undef, 'a run with no files never draws' );

done_testing;
