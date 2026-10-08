package Puff::Rule::Security::TwoArgOpen;

use v5.36;
use parent 'Puff::Rule';

use Puff::PPIUtil qw( is_builtin_call call_args );

sub code       {'S002'}
sub summary    {'Use three-argument open'}
sub applies_to {'PPI::Token::Word'}
sub fix_safety {'unsafe'}

sub explanation {
    return <<~'END';
        Two-argument open takes the mode and the filename from one string, so
        a filename that comes from outside the program can choose the mode.
        A name ending in `|` runs it as a command, one starting with `|` pipes
        into a command, `>` or `>>` at the start writes to or truncates a
        file, `&` duplicates a filehandle and `-` opens STDIN or STDOUT.
        Three-argument open passes the mode separately and takes the filename
        literally.

        The fix rewrites `open(FH, "<$file")` as `open(FH, '<', $file)` and
        `open(FH, $file)` as `open(FH, '<', $file)`. It only handles a second
        argument that is a single '...' or "..." string or a single scalar
        variable, and declines when the string is empty, starts with `|` or
        `&`, ends with `|`, is `-`, has a filename starting with `&` or equal
        to `-`, has a mode but no filename, is a "..." string starting with a
        variable (the mode could be inside it), or is a "..." string with an
        escape such as \t or \n at the start or end of the mode or filename
        (whitespace that two-argument open strips at runtime). Declined calls
        are reported as not fixable.

        The fix is unsafe because it changes behaviour:
        - two-argument open trims whitespace around the filename and
          three-argument open does not;
        - a filename containing a mode, pipe, `&` or `-` is now taken
          literally, which is the point, but code that relied on passing a
          mode or a command through the variable stops working;
        - a scalar holding a reference (such as `\$buffer`) becomes an
          in-memory open instead of opening a file named after the
          stringified reference.
        END
}

sub check ( $self, $elem, $doc ) {
    return unless $elem->content eq 'open' && is_builtin_call($elem);
    my $args = call_args($elem);
    return unless @$args == 2;
    return $self->violation(
        $elem,
        message => 'Use three-argument open',
        fixable => defined _replacement( $args->[1] ) ? 1 : 0,
    );
}

sub fix ( $self, $violation, $fix ) {
    my $args = call_args( $violation->element );
    return 0 unless @$args == 2;
    my $text = _replacement( $args->[1] ) // return 0;
    $fix->replace( $args->[1][0], $text );
    return 1;
}

# The text that replaces the second argument (a list of significant
# elements), or undef when the call should not be fixed.
sub _replacement ($arg) {
    return unless @$arg == 1;
    my ($el) = @$arg;

    if ( $el->isa('PPI::Token::Symbol') ) {
        return unless $el->content =~ /\A\$/;
        return "'<', " . $el->content;
    }

    my $double = $el->isa('PPI::Token::Quote::Double');
    return unless $double || $el->isa('PPI::Token::Quote::Single');
    my $q = $double ? '"' : q{'};
    my $s = $el->string;

    return if $s eq '' || $s =~ /\A[|&]/ || $s =~ /\|\z/ || $s eq '-';
    return if $double && $s =~ /\A\s*[\$\@]/;

    # An escape such as \t or \n at either end is whitespace that two-arg
    # open strips at runtime and three-arg open keeps.
    return if $double && ( $s =~ /\A\s*\\/ || $s =~ /\\.\s*\z/s );

    if ( $s =~ /\A\s*(\+?(?:>>|<|>))\s*(.*?)\s*\z/s ) {
        my ( $mode, $file ) = ( $1, $2 );
        return if $file eq '' || $file =~ /\A&/ || $file eq '-';
        return if $double && $file =~ /\A\\/;
        my $quoted = $double && $file =~ /\A\$[A-Za-z_]\w*\z/ ? $file : "$q$file$q";
        return "'$mode', $quoted";
    }
    return if $s =~ /\A\s|\s\z/;
    return "'<', " . $el->content;
}

1;

# ABSTRACT: S002 - Use three-argument open

__END__

=pod

=head1 DESCRIPTION

Reports calls to the built-in C<open> with exactly two arguments.

The unsafe fix splits a C<'...'> or C<"..."> second argument into a mode and
a filename (C<"E<lt>$file"> becomes C<'E<lt>', $file>), or adds C<'E<lt>'>
before a filename with no mode or a single scalar variable. Anything else,
including pipes, C<&> duplication, C<->, other quote styles and expressions,
is reported with C<fixable> 0.

=cut
