package Puff::Rule::Security::TwoArgOpen;

use v5.36;
use parent 'Puff::Rule';

use Puff::PPIUtil qw( is_builtin_call call_args is_constant_string );

# Two-argument open trims only ASCII whitespace (space, \t, \n, \x0B, \f,
# \r) and keeps U+00A0, U+2028 and the like in the filename, so every \s
# below takes /a.

# A whole escape sequence at the end of a "..." string: it may stand for
# whitespace (\x20, \040, \x{20}, \o{40}, \N{SPACE}, \t, ...).
my $TRAILING_ESCAPE = qr/\\(?:x\{[^}]*\}|x[0-9a-fA-F]{0,2}|o\{[^}]*\}|[0-7]{1,3}|N\{[^}]*\}|c.|.)\s*\z/as;

sub code       {'S002'}
sub summary    {'Use three-argument open'}
sub applies_to {'PPI::Token::Word'}
sub fix_safety {'unsafe'}
sub cwe        { ( 78, 73 ) }

sub explanation {
    return <<~'END';
        Two-argument open takes the mode and the filename from one string, so
        a filename that comes from outside the program can choose the mode.
        A name ending in `|` runs it as a command, one starting with `|` pipes
        into a command, `>` or `>>` at the start writes to or truncates a
        file, `&` duplicates a filehandle and `-` opens STDIN or STDOUT.
        Three-argument open passes the mode separately and takes the filename
        literally.

        `open($fh, '-|')` and `open($fh, '|-')`, which fork instead of opening
        anything, are not reported.

        The fix rewrites `open(FH, "<$file")` as `open(FH, '<', $file)` and
        `open(FH, $file)` as `open(FH, '<', $file)`. It only handles a second
        argument that is a single '...' or "..." string or a single scalar
        variable, and declines when the string is empty, starts with `|` or
        `&`, ends with `|`, is `-` or starts with `-` and NUL, has a filename
        starting with `&`, has a filename that is `-` or starts with `-` and
        ASCII whitespace, `:` or NUL (all of these open STDIN or STDOUT), has
        a mode but no filename, is a "..." string starting with a variable
        (the mode could be inside it), or is a "..." string with an escape
        right after such a `-` or with an escape such as \t, \n, \x20, \040
        or \x{20} at the start or end of the mode or filename (whitespace
        that two-argument open strips at runtime). Declined calls are
        reported as not fixable.

        Two-argument open strips only ASCII whitespace. A non-ASCII space such
        as U+00A0 or U+2028 at either end of the filename is part of the
        name, so the fix keeps it there.

        The fix is unsafe because it changes behaviour:
        - two-argument open trims ASCII whitespace around the filename and
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
    return if _is_fork_open( $args->[1] );
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

# open($fh, '-|') and open($fh, '|-') fork; they open no file and run no
# command, and have no three-argument form.
sub _is_fork_open ($arg) {
    return 0 unless @$arg == 1 && $arg->[0]->isa('PPI::Token::Quote') && is_constant_string( $arg->[0] );
    return $arg->[0]->string =~ /\A\s*(?:-\||\|-)\s*\z/a;
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

    return if $s eq '' || $s =~ /\A[|&]/ || $s =~ /\|\z/;

    # "-" alone, or followed by NUL, opens STDIN. An escape after the "-"
    # might be NUL.
    return if $s =~ /\A\s*-(?:\z|\0|\\)/a;
    return if $double && $s =~ /\A\s*[\$\@]/a;

    # An escape such as \t or \n at either end is whitespace that two-arg
    # open strips at runtime and three-arg open keeps.
    return if $double && ( $s =~ /\A\s*\\/a || $s =~ $TRAILING_ESCAPE );

    if ( $s =~ /\A\s*(\+?(?:>>|<|>))\s*(.*?)\s*\z/as ) {
        my ( $mode, $file ) = ( $1, $2 );
        return if $file eq '' || $file =~ /\A&/;

        # After a mode, "-" alone or followed by ASCII whitespace, ":" or NUL
        # opens STDIN or STDOUT. An escape after the "-" might be one of
        # those.
        return if $file =~ /\A-(?:\z|[\s:\0\\])/a;
        return if $double && ( $file =~ /\A\\/ || $file =~ $TRAILING_ESCAPE );
        my $quoted = $double && $file =~ /\A\$[A-Za-z_]\w*\z/ ? $file : "$q$file$q";
        return "'$mode', $quoted";
    }
    return if $s =~ /\A\s|\s\z/a;
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
including pipes, C<&> duplication, C<-> (alone, or followed by whitespace,
C<:> or NUL, which perl also treats as STDIN or STDOUT), other quote styles
and expressions, is reported with C<fixable> 0.

=cut
