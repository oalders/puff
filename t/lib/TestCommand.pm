package TestCommand;

use v5.36;

use Exporter qw( import );
use POSIX    ();

our @EXPORT_OK = qw( run_capture );

# Runs @cmd without a shell and returns its stdout; $? holds its status.
# STDERR goes to the file $stderr, or into the returned output if $stderr
# is undef.
sub run_capture ( $stderr, @cmd ) {
    my $pid = open( my $fh, '-|' ) // die "fork: $!";
    if ( !$pid ) {
        if ( defined $stderr ) {
            open STDERR, '>', "$stderr" or POSIX::_exit(126);
        }
        else {
            open STDERR, '>&', \*STDOUT or POSIX::_exit(126);
        }
        exec { $cmd[0] } @cmd;
        POSIX::_exit(127);
    }
    my $out = do { local $/; <$fh> } // q{};
    close $fh;
    return $out;
}

1;
