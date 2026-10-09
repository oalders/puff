package Puff::Reporter::JSON;

use v5.36;

use JSON::PP             ();
use Puff::Reporter::Text ();

sub new ( $class, %args ) {
    return bless {}, $class;
}

sub report ( $self, $run, $out, $err ) {
    my @files = sort { $a->{file} cmp $b->{file} } @{ $run->{files} };
    Puff::Reporter::Text->report_errors( \@files, $err );
    my @items;
    for my $file (@files) {
        push @items, map { $self->violation_data($_) } @{ $file->{violations} };
    }
    print {$out} JSON::PP->new->canonical->pretty->encode( \@items );
    Puff::Reporter::Text->flush_or_die($out);
    return;
}

# The JSON-ready hash for one remaining violation; Puff::Reporter::JSONL
# uses it too.
sub violation_data ( $class, $v ) {
    return {
        code    => $v->code,
        message => $v->message,
        file    => $v->file,
        line    => $v->line + 0,
        column  => $v->column + 0,
        fix     => {
            safety    => $v->rule ? $v->rule->fix_safety : 'none',
            available => $v->fixable ? JSON::PP::true : JSON::PP::false,
            applied   => JSON::PP::false,
        },
    };
}

1;

# ABSTRACT: Report results as JSON

__END__

=pod

=head1 SYNOPSIS

    Puff::Reporter::JSON->new->report( $run, \*STDOUT, \*STDERR );

=head1 DESCRIPTION

Prints a JSON array with one object per remaining violation, sorted by
file, line and column:

    { "code": "S002", "message": "...", "file": "lib/Foo.pm",
      "line": 12, "column": 5,
      "fix": { "safety": "unsafe", "available": true, "applied": false } }

C<safety> is the rule's fix safety (C<safe>, C<unsafe> or C<none>);
C<available> says whether a fix is offered for this violation; C<applied>
is always false, because only violations that remain are listed. The
output is character data: give it a handle with an encoding layer. File
errors go to the error handle.

C<< Puff::Reporter::JSON->violation_data($violation) >> returns the hash
above for one violation.

=cut
