package Puff::Reporter::JSONL;

use v5.36;

use JSON::PP             ();
use Puff::Reporter::JSON ();
use Puff::Reporter::Text ();

sub new ( $class, %args ) {
    return bless {
        out  => $args{out},                        # where start and file events go, as they happen
        mode => $args{mode} // 'lint',             # lint, fix or diff
        json => JSON::PP->new->canonical->ascii,
    }, $class;
}

sub start ( $self, $total ) {
    $self->_emit( $self->{out}, { type => 'start', total => $total + 0 } );
    return;
}

sub file ( $self, $result ) {
    my %event = (
        type          => 'file',
        file          => $result->{file},
        error         => $result->{error},
        fixes_skipped => $result->{fixes_skipped},
        fixed         => $result->{written} ? $result->{fixed_count} + 0 : 0,
        violations    => [ map { Puff::Reporter::JSON->violation_data($_) } @{ $result->{violations} // [] } ],
    );
    $event{diff} = $result->{diff} if $self->{mode} eq 'diff';
    $self->_emit( $self->{out}, \%event );
    return;
}

sub report ( $self, $run, $out, $err ) {
    $self->_emit( $out, { type => 'done', exit_code => $run->{exit_code} + 0 } );
    return;
}

# Prints a final done event for a run that died: the exit code puff will
# return and the error, so the stream still ends with done.
sub abort ( $self, $exit_code, $error ) {
    $self->_emit( $self->{out}, { type => 'done', exit_code => $exit_code + 0, error => "$error" =~ s/\s+\z//r } );
    return;
}

sub _emit ( $self, $out, $event ) {
    print {$out} $self->{json}->encode($event), "\n";
    Puff::Reporter::Text->flush_or_die($out);
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
    $jsonl->report( $run, \*STDOUT, \*STDERR );    # or, if run dies: $jsonl->abort( 2, $@ )

=head1 DESCRIPTION

Prints one compact JSON object per C<\n>-terminated line, flushing after
each, so a consumer can follow a run as it goes. The output is pure ASCII:
every non-ASCII character is written as a C<\u> escape, so characters such
as U+2028, U+2029 and U+0085 never appear raw where a Unicode-aware line
splitter could break a line on them. Every object has a C<type>:

=over 4

=item C<start>

    {"total":250,"type":"start"}

Printed once, before any file is checked, as the first line. C<total> is
the number of files the run will check (including paths that do not
exist). If puff fails before the files are found, there is no C<start>:
the stream is just C<done> with C<error>.

=item C<file>

    {"error":null,"file":"lib/Foo.pm","fixed":0,"fixes_skipped":null,"type":"file","violations":[...]}

Printed once per file, in the order the files are checked (not sorted), as
soon as each is done. C<violations> lists the remaining violations, each
the same object L<Puff::Reporter::JSON> prints. C<error> is the file's error
(read, parse, rule, engine, fix or write failure, or
C<No such file or directory>) or null; errors are not printed to the error
handle. C<fixes_skipped> is the reason fixes were not applied to the file
(such as C<CR or CRLF line endings: fixes not applied>) or null; it is not
printed to the error handle either. C<fixed> is the number of fixes written
to the file: 0 unless C<--fix> rewrote it, and always 0 with C<--diff>,
whose pending fixes are in C<diff>. With C<--diff>, there is also a C<diff>
key: the unified diff for the file, or null when nothing would change.

=item C<done>

    {"exit_code":1,"type":"done"}

    {"error":"...","exit_code":2,"type":"done"}

Printed last: C<done> is always the last line of any run that does not
crash outright.
C<exit_code> is the exit code puff returns. If the run dies part way
(C<abort>), C<done> also has C<error>, the message puff prints to STDERR,
and C<exit_code> is 2. A stream that ends without C<done> means puff was
killed or aborted before it could print one: treat it as a failure.

=back

More event types, and more keys in any event, may be added later: ignore
any C<type> or key you do not know. C<message>, C<error>, C<fixes_skipped>,
C<file> and C<diff> contain text derived from the linted files (their
names and contents): consumers should treat it as untrusted data.

C<start>, C<file> and C<abort> print to the C<out> handle given to C<new>,
as the run progresses; C<report> prints C<done> to the C<$out> handle it is
given. Its C<$err> handle is unused, since jsonl puts errors in C<file>
events.

=cut
