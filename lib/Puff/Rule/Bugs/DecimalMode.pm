package Puff::Rule::Bugs::DecimalMode;

use v5.36;
use parent 'Puff::Rule';

use Puff::PPIUtil qw( decimal_mode );

sub code            {'B010'}
sub summary         {'File mode given as a decimal literal'}
sub applies_to      {'PPI::Token::Number'}
sub fix_safety      {'unsafe'}
sub explicit_select {1}

sub explanation {
    return <<~'END';
        File modes are octal, but a number literal without a leading zero
        is decimal:

            chmod 755, $file;    # mode 01363, not 0755
            umask 22;            # mask 026, not 022
            mkdir $dir, 777;     # mode 01411, not 0777

        The rule reports a decimal literal of three or four digits, all 0
        to 7, that is the whole mode argument of:

        - `chmod`, `umask`, `mkdir`, `mkfifo`, `POSIX::mkfifo`, `dbmopen`,
          `sysopen` and File::Path's legacy `mkpath($dir, $verbose, $mode)`;
        - the `mode`, `chmod` or `mask` value in an options hash passed to
          File::Path's `make_path` or `mkpath`, or to a `->mkdir` or
          `->mkpath` method (Path::Tiny);
        - a `->chmod(...)` method call with that one argument (Path::Tiny).
          Strings such as `'0755'` and `'u+x'` are not reported.

        `umask` with two digits (`umask 22`, `umask 77`) is reported too,
        since `022`, `027` and `077` are its usual values. One digit is the
        same in decimal and octal, and other two-digit modes are rare, so
        neither is reported. Neither are literals with an 8 or 9, octal
        (`0755`, `0o755`), hex or binary literals, `oct('755')`, variables
        and expressions.

        Method calls cannot be typed, so any object's `chmod`, `mkdir` or
        `mkpath` method is checked, which can report a class whose method
        really does take a decimal number.

        The fix adds the leading zero, so `755` becomes `0755`. It is
        unsafe because it changes the mode the code sets. B003 does not
        report the fixed literal. S009 reads a decimal mode as the octal
        one it was meant to be, so `chmod 777, $dir` is reported by both
        rules: here for the missing zero, there for the world-writable
        mode.

        This rule is not selected by `B`; select it by code or with `ALL`.
        END
}

sub check ( $self, $elem, $doc ) {
    my $call   = decimal_mode($elem) // return;
    my $digits = $elem->content;
    return $self->violation(
        $elem,
        message => sprintf(
            '%s mode %s is decimal (octal %#o); write 0%s',
            $call, $digits, $digits, $digits
        ),
    );
}

sub fix ( $self, $violation, $fix ) {
    my $elem = $violation->element;
    return 0 unless defined decimal_mode($elem);
    $fix->replace( $elem, '0' . $elem->content );
    return 1;
}

1;

# ABSTRACT: B010 - file mode given as a decimal literal

__END__

=pod

=head1 DESCRIPTION

Reports a file mode written as a decimal literal, such as C<chmod 755, $f>,
C<umask 22> or C<< make_path( $dir, { mode => 711 } ) >>, where the octal
C<0755> was meant. The unsafe fix adds the leading zero.

Not selected by C<B>: select it by its exact code or with C<ALL>. See
L<Puff::Rule/explicit_select>.

=cut
