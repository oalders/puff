package Puff::Reporter::JSONL;

use v5.36;

use IO::Handle           ();
use JSON::PP             ();
use Puff::Reporter::JSON ();

sub new ( $class, %args ) {
    return bless {
        out  => $args{out},                # where start and file events go, as they happen
        mode => $args{mode} // 'lint',    # lint, fix or diff
        json => JSON::PP->new->canonical,
    }, $class;
}

sub start ( $self, $total ) {
    $self->_emit( $self->{out}, { type => 'start', total => $total + 0 } );
    return;
}

sub file ( $self, $result ) {
    my %event = (
        type       => 'file',
        file       => $result->{file},
        error      => $result->{error},
        fixed      => $result->{written} ? $result->{fixed_count} + 0 : 0,
        violations => [ map { Puff::Reporter::JSON->violation_data($_) } @{ $result->{violations} // [] } ],
    );
    $event{diff} = $result->{diff} if $self->{mode} eq 'diff';
    $self->_emit( $self->{out}, \%event );
    return;
}

sub report ( $self, $run, $out, $err ) {
    for my $file ( @{ $run->{files} } ) {
        print {$err} "$file->{file}: $file->{fixes_skipped}\n" if defined $file->{fixes_skipped};
    }
    $self->_emit( $out, { type => 'done', exit_code => $run->{exit_code} + 0 } );
    return;
}

sub _emit ( $self, $out, $event ) {
    print {$out} $self->{json}->encode($event), "\n";
    $out->flush;
    return;
}

1;

# ABSTRACT: Stream results as JSON Lines

__END__

=pod

=head1 SYNOPSIS

    my $jsonl  = Puff::Reporter::JSONL->new( out => \*STDOUT, mode => 'lint' );
    my $runner = Puff::Runner->new(
        config   => $config,
        engine   => $engine,
        progress => sub ( $done, $total ) { $jsonl->start($total) unless $done },
        on_file  => sub ($result) { $jsonl->file($result) },
    );
    my $run = $runner->run(@paths);
    $jsonl->report( $run, \*STDOUT, \*STDERR );

=head1 DESCRIPTION

Prints one compact JSON object per line, flushing after each, so a consumer
can follow a run as it goes. Every object has a C<type>:

=over 4

=item C<start>

    {"total":250,"type":"start"}

Printed once, before any file is checked. C<total> is the number of files
the run will check (including paths that do not exist).

=item C<file>

    {"error":null,"file":"lib/Foo.pm","fixed":0,"type":"file","violations":[...]}

Printed once per file, in the order the files are checked (not sorted), as
soon as each is done. C<violations> lists the remaining violations, each
the same object L<Puff::Reporter::JSON> prints. C<error> is the file's error
(read, parse, rule, engine, fix or write failure, or
C<No such file or directory>) or null; errors are not printed to the error
handle. C<fixed> is the number of fixes written to the file: 0 unless
C<--fix> rewrote it. With C<--diff>, there is also a C<diff> key: the
unified diff for the file, or null when nothing would change.

=item C<done>

    {"exit_code":1,"type":"done"}

Printed last. C<exit_code> is the exit code puff returns.

=back

More event types, and more keys in any event, may be added later: ignore
any C<type> or key you do not know. The output is character data: give it
a handle with an encoding layer. Notices that fixes were not applied
(C<fixes_skipped>, such as for CRLF files) still go to the error handle.

C<start> and C<file> print to the C<out> handle given to C<new>, as the
run progresses; C<report> prints C<done> to the handle it is given.

=cut
