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
        since `022`, `027` and `077` are its usual values; the message calls
        its argument a mask rather than a mode. One digit is the same in
        decimal and octal, and other two-digit modes are rare, so neither is
        reported. Neither are literals with an 8 or 9, octal (`0755`,
        `0o755`), hex or binary literals, `oct('755')`, variables and
        expressions.

        A literal whose decimal value is a common mode or umask is taken as
        deliberate: `mkdir $dir, 511` is 0777, `chmod 493, $f` is 0755 and
        `umask 18` is 022. The list is the decimals of 0777, 0775, 0770,
        0755, 0750, 0711, 0700, 0666, 0664, 0660, 0644, 0640, 0600, 0444,
        0400, 022, 027, 077, 002 and 007.

        Method calls cannot be typed, so any object's `chmod`, `mkdir` or
        `mkpath` method is checked, which can report a class whose method
        really does take a decimal number. Only the options-hash form of
        `->mkdir` and `->mkpath` is checked; a positional mode such as
        `$p->mkdir( $dir, 755 )` is not.

        The fix adds the leading zero, so `755` becomes `0755`. It is
        unsafe because it changes the mode the code sets, and the new mode
        can be wider than the accidental one: `chmod 664, $f` really sets
        01230, and the fix makes it 0664, which is world-readable. Review
        each fixed mode. B003 skips the same mode positions, so it does not
        report the fixed literal unless its `strict` option is on, which
        reports a leading zero in every mode. S009 checks a decimal mode or
        mask both as its real value and as the octal one it was meant to be,
        so `chmod 777, $dir` is reported by both rules: here
        for the missing zero, there for the world-writable mode it would be.

        This rule is not selected by `B`; select it by code or with `ALL`.
        END
}

sub check ( $self, $elem, $doc ) {
    my $call   = decimal_mode($elem) // return;
    my $digits = $elem->content;
    my $noun   = $call eq 'umask' ? 'mask' : 'mode';
    return $self->violation(
        $elem,
        message => sprintf(
            '%s %s %s is decimal (octal %#o); write 0%s',
            $call, $noun, $digits, $digits, $digits
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
C<0755> was meant. A literal whose decimal value is a common mode
(C<mkdir $d, 511> is 0777) is taken as deliberate. Only the options-hash
form of C<< ->mkdir >> and C<< ->mkpath >> is checked, not a positional
mode.

The unsafe fix adds the leading zero. That sets the mode the author wrote,
which can be wider than the accidental one: C<chmod 664, $f> really sets
01230, and the fix makes it 0664, which is world-readable. Review each fixed
mode.

Not selected by C<B>: select it by its exact code or with C<ALL>. See
L<Puff::Rule/explicit_select>.

=cut
