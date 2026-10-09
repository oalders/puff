package Puff::Reporter::JSONL;

use v5.36;

use IO::Handle           ();
use JSON::PP             ();
use Puff::Reporter::JSON ();

sub new ( $class, %args ) {
    my $out = $args{out};
    $out->autoflush(1);
    return bless { out => $out, json => JSON::PP->new->canonical, started => 0 }, $class;
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
            type       => 'file',
            file       => $result->{file},
            error      => $result->{error},
            violations => [ map { Puff::Reporter::JSON::violation($_) } @{ $result->{violations} // [] } ],
            fixed      => $result->{fixed_count} // 0,
            diff       => $result->{diff},
        } );
    };
}

sub report ( $self, $run, $out, $err ) {
    $self->_emit( { type => 'done', exit_code => $run->{exit_code} } );
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
    {"diff":null,"error":null,"file":"lib/Foo.pm","fixed":0,"type":"file","violations":[...]}
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
(C<--fix>) or would be (C<--diff>). C<diff> is the unified diff in C<--diff>
mode when the file would change, else null.

=item C<done>

Comes last. C<exit_code> is the code puff exits with.

=back

Later versions may add event types and fields, so readers should ignore ones
they do not know. The output is character data: give C<out> an encoding layer.

=cut
