use File::Temp qw(tempfile);
my ( $fh, $name ) = tempfile( DIR => '/tmp' );
my $d = $ENV{TMPDIR} || '/tmp';
$d = '/tmp/';
$d = '/tmpfoo/x';
$d = '/home/tmp/x';
my %h = ( mktemp => 1 );
$h{mktemp} = 2;
$fh->mktemp('x');
sub tmpnam { return 1 }
print 'tmp/x';
