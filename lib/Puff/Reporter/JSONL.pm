package Puff::Reporter::JSONL;

use v5.36;

use IO::Handle           ();
use JSON::PP             ();
use Puff::Reporter::JSON ();

sub new ( $class, %args ) {
    my $out = $args{out};
    $out->autoflush(1);
    return bless { out => $out, json => JSON::PP->new->canonical->ascii, started => 0 }, $class;
}

# A progress callback for Puff::Runner: the first call says how many files
# will be checked.
sub progress ($self) {
    return sub ( $done, $total ) {
        $self->_emit( { type => 'start', total => $total } ) unless $self->{started}++;
    };
}

# An on_file callback for Puff::Runner.
sub on_file ($self) {
    return sub ($result) {
        $self->_emit( {
            type          => 'file',
            file          => $result->{file},
            error         => $result->{error},
            violations    => [ map { Puff::Reporter::JSON::violation($_) } @{ $result->{violations} // [] } ],
            fixed         => $result->{fixed_count} // 0,
            fixes_skipped => $result->{fixes_skipped},
            diff          => $result->{diff},
        } );
    };
}

sub report ( $self, $run, $out, $err ) {
    $self->_emit( { type => 'done', exit_code => $run->{exit_code} } );
    return;
}

# Ends the stream when the run dies.
sub fatal ( $self, $error ) {
    $self->_emit( { type => 'done', exit_code => 2, error => "$error" =~ s/\s+\z//r } );
    return;
}

sub _emit ( $self, $event ) {
    print { $self->{out} } $self->{json}->encode($event), "\n";
    return;
}

1;

# ABSTRACT: Stream results as JSON Lines

__END__

=pod

=head1 SYNOPSIS

    my $reporter = Puff::Reporter::JSONL->new( out => \*STDOUT );
    my $runner   = Puff::Runner->new(
        %args,
        progress => $reporter->progress,
        on_file  => $reporter->on_file,
    );
    $reporter->report( $runner->run(@paths), \*STDOUT, \*STDERR );

=head1 DESCRIPTION

Writes one JSON object per line to C<out> while the run is in progress, and
flushes after each line, so a program reading puff's output can act on each
file as soon as it is checked. Every object has a C<type>:

    {"total":250,"type":"start"}
    {"diff":null,"error":null,"file":"lib/Foo.pm","fixed":0,"fixes_skipped":null,"type":"file","violations":[...]}
    {"exit_code":1,"type":"done"}

=over

=item C<start>

Comes first, once the files have been found. C<total> is how many file
events will follow.

=item C<file>

One per file, in the order the files are checked. C<violations> are the
violations that remain, in the shape the C<json> format uses (see
L<Puff::Reporter::JSON>). C<error> is the reason the file could not be read,
parsed, fixed or written (or the path does not exist), else null; errors are
not printed to the error handle. C<fixed> is how many fixes were applied
(C<--fix>) or would be (C<--diff>). C<fixes_skipped> is the reason fixes
were wanted but not applied (CR or CRLF line endings), else null. C<diff> is
the unified diff in C<--diff> mode when the file would change, else null.

=item C<done>

Comes last. C<exit_code> is the code puff exits with. When the run dies
part way (see C<fatal>), C<exit_code> is 2 and C<error> is the message. A
stream that ends without C<done>, because puff was killed, is a failure.

=back

Only per-file errors are events. Usage, config and rule-loading errors
happen before the reporter exists: they go to STDERR as text, with exit 2
and no events.

Later versions may add event types and fields, so readers should ignore ones
they do not know. Every string (C<file>, C<error>, C<message>, C<diff>) is
untrusted text from the files being checked: sanitise it before printing it
to a terminal. The output is pure ASCII, with every other character
C<\u>-escaped (U+2028 and U+0085 included), so each event is exactly one
line.

=head1 METHODS

=head2 new( out => $fh )

All events go to C<$fh>, which is set to autoflush.

=head2 progress, on_file

Callbacks for L<Puff::Runner>: the first C<progress> call writes C<start>,
and each C<on_file> call writes a C<file> event.

=head2 report( $run, $out, $err )

Writes C<done> for the result of L<Puff::Runner/run>. It writes to the
handle given to C<new>; C<$out> and C<$err> are ignored, and are there
so it can be called like the other reporters.

=head2 fatal($error)

Writes C<done> with exit code 2 and C<$error>, trailing whitespace removed.
Call it when L<Puff::Runner/run> dies, then rethrow.

=cut
