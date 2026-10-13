package Puff::Rule::Security::WorldWritable;

use v5.36;
use parent 'Puff::Rule';

use Puff::PPIUtil qw( is_builtin_call call_args is_constant_string decimal_mode );

my $OTHER_WRITE = oct('0002');
my $STICKY      = oct('01000');

sub code       {'S009'}
sub summary    {'Do not make files world-writable'}
sub applies_to {'PPI::Token::Word'}
sub cwe        {732}

sub explanation {
    return <<~'END';
        A world-writable file or directory lets any local user change it:
        replace a script, a config file or a cache your program trusts later
        (CWE-732).

        The rule reports:

        - `chmod` with a constant mode that has the other-write bit (0002),
          such as `chmod 0777, $dir` or `chmod 0666, $file`;
        - a `->chmod` method call (Path::Tiny, IO::All) with such a number, or
          with a symbolic mode that gives others write access (`'o+w'`,
          `'a+rw'`);
        - `umask` with a constant mask that does not mask other-write, such
          as `umask 0` or `umask 0020`, which leaves every file the program
          creates afterwards world-writable.

        A mode with the sticky bit (`chmod 01777, $dir`) is not reported,
        since that is how a shared directory such as /tmp is meant to be set
        up. Modes passed to `mkdir`, `sysopen` and File::Path's `make_path`
        are not reported: the umask filters them, so 0777 there is the normal
        default. Modes in variables are not checked.

        A mode written in decimal is checked twice: as the mode the code
        really sets, and as the octal mode it was probably meant to be (see
        B010, which reports the missing zero). Either one is reported, and
        the message says which:

        - `chmod 755, $f` really sets 01363, which is other-writable, and
          `umask 77` really sets the mask 0115, which does not mask it:
          "decimal 755 is mode 01363, which is other-writable" and "decimal
          77 is mask 0115, which leaves new files other-writable";
        - `chmod 777, $dir` really sets 01411, which is not, but the 0777 it
          was meant to be is: "decimal 777 is mode 01411; read as octal 0777
          it would make the file world-writable".

        Messages about the mode a decimal literal really sets say
        "other-writable"; "world-writable" describes the octal mode it was
        meant to be.

        The sticky bit never exempts the mode a decimal literal really sets,
        whether it is there by accident (755 is 01363, 999 is 01747) or was
        meant (`chmod 1755, $f` really sets 03333, which is other-writable):
        the file it lands on is not the shared directory the author had in
        mind. Only the octal reading keeps the exemption, so `chmod 1777,
        $d`, which really sets 03361, is not reported. A decimal literal
        whose value is a common mode (`chmod 511, $f` is 0777) is taken as
        written.

        Use 0755 or 0644, or 0700 and 0600 for anything private. There is no
        fix.

        Ruff's equivalent is S103.
        END
}

my %CHMOD = (
    noun  => 'mode',
    bad   => sub ($m) { $m & $OTHER_WRITE && !( $m & $STICKY ) },
    is    => 'makes the file world-writable',
    which => 'which is other-writable',
    would => 'it would make the file world-writable',
    use   => 'use 0755 or 0644',
);
my %UMASK = (
    noun  => 'mask',
    bad   => sub ($m) { !( $m & $OTHER_WRITE ) },
    is    => 'leaves new files world-writable',
    which => 'which leaves new files other-writable',
    would => 'it would leave new files world-writable',
    use   => 'use 022 or 077',
);

sub check ( $self, $elem, $doc ) {
    my $name      = $elem->content =~ s/\ACORE:://r;
    my $prev      = $elem->sprevious_sibling;
    my $is_method = $prev && $prev->isa('PPI::Token::Operator') && $prev->content eq '->';

    if ( $name eq 'chmod' && ( $is_method || is_builtin_call($elem) ) ) {
        my $args = call_args($elem);
        return unless @$args && @{ $args->[0] } == 1;
        my $mode = $args->[0][0];
        if ( $mode->isa('PPI::Token::Number') ) {
            my $message = _message( 'chmod', $mode, \%CHMOD ) // return;
            return $self->violation( $elem, message => $message );
        }
        return unless $is_method && is_constant_string($mode) && _symbolic_other_write( $mode->string );
        return $self->violation( $elem, message => "chmod ${\ $mode->content } $CHMOD{is} (CWE-732); $CHMOD{use}" );
    }

    if ( $name eq 'umask' && !$is_method && is_builtin_call($elem) ) {
        my $args = call_args($elem);
        return unless @$args == 1 && @{ $args->[0] } == 1;
        my $message = _message( 'umask', $args->[0][0], \%UMASK ) // return;
        return $self->violation( $elem, message => $message );
    }
    return;
}

# A number literal is checked as the value the code really sets and, for a
# decimal literal that was probably meant as octal (`chmod 777, $f`; see
# decimal_mode), as that octal reading too. The real value wins: a decimal
# literal whose real value is fine is reported only for the octal reading,
# with a message that says the code does not set it. The sticky bit never
# excuses the real value of any decimal integer literal, whether or not
# decimal_mode takes it for octal: whether the bit is an accident (755 is
# 01363, 999 is 01747) or meant (1755 is 03333), the file it lands on is
# almost certainly not a shared directory. Octal, hex and binary literals,
# and the octal reading, keep the exemption.
sub _message ( $call, $elem, $how ) {
    return undef unless $elem->can('literal');
    my $real   = $elem->literal // return undef;
    my $digits = $elem->content;
    my $what   = "$call $digits";
    my $tail   = "(CWE-732); $how->{use}";
    my $meant  = decimal_mode($elem) ? oct $digits : undef;

    # Float, Exp, Octal, Hex and Binary are all subclasses.
    if ( $how->{bad}->( ref $elem eq 'PPI::Token::Number' ? $real & ~$STICKY : $real ) ) {
        my $decimal = $real >= 8 && !grep { $elem->isa("PPI::Token::Number::$_") } qw( Octal Hex Binary );
        return "$what $how->{is} $tail" unless $decimal;
        return sprintf '%s: decimal %s is %s %#o, %s %s', $what, $digits, $how->{noun}, $real, $how->{which}, $tail;
    }
    return undef unless defined $meant && $how->{bad}->($meant);
    return sprintf '%s: decimal %s is %s %#o; read as octal 0%s %s %s', $what, $digits, $how->{noun}, $real,
        $digits, $how->{would}, $tail;
}

# 'o+w', 'a=rw', 'u+x,o+w'
sub _symbolic_other_write ($mode) {
    return scalar grep {/\A[ugo]*[ao][ugoa]*[+=][rwxXst]*w/} split /,/, $mode;
}

1;

# ABSTRACT: S009 - do not make files world-writable

__END__

=pod

=head1 DESCRIPTION

Reports C<chmod> with a constant world-writable mode and C<umask> with a
constant mask that does not mask other-write. A decimal mode such as
C<chmod 755, $f> is checked both as the mode it really sets (01363) and as
the octal mode it was probably meant to be (0755), and the message says
which one is the problem. The sticky bit exempts only the octal reading, not
the mode a decimal literal really sets: C<chmod 1755, $f> really sets 03333,
which is other-writable, and is reported. Messages about the real mode of a
decimal literal say "other-writable"; "world-writable" describes the octal
mode it was meant to be. There is no fix.

=cut
