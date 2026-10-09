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

        A mode written in decimal, such as `chmod 777, $dir` or `umask 20`,
        is read as the octal mode it was meant to be (0777, 020), since that
        is what the code will do once the missing zero is added. B010
        reports the missing zero; this rule reports the world-writable mode.

        Use 0755 or 0644, or 0700 and 0600 for anything private. There is no
        fix.

        Ruff's equivalent is S103.
        END
}

sub check ( $self, $elem, $doc ) {
    my $name      = $elem->content =~ s/\ACORE:://r;
    my $prev      = $elem->sprevious_sibling;
    my $is_method = $prev && $prev->isa('PPI::Token::Operator') && $prev->content eq '->';

    if ( $name eq 'chmod' && ( $is_method || is_builtin_call($elem) ) ) {
        my $args = call_args($elem);
        return unless @$args && @{ $args->[0] } == 1;
        my $mode = $args->[0][0];
        my $bad  = _number($mode) // -1;
        if ( $bad >= 0 ) {
            return unless $bad & $OTHER_WRITE && !( $bad & $STICKY );
        }
        else {
            return unless $is_method && is_constant_string($mode) && _symbolic_other_write( $mode->string );
        }
        return $self->violation(
            $elem,
            message => 'chmod ' . $mode->content . ' makes the file world-writable (CWE-732); use 0755 or 0644'
        );
    }

    if ( $name eq 'umask' && !$is_method && is_builtin_call($elem) ) {
        my $args = call_args($elem);
        return unless @$args == 1 && @{ $args->[0] } == 1;
        my $mask = _number( $args->[0][0] ) // return;
        return if $mask & $OTHER_WRITE;
        return $self->violation(
            $elem,
            message => 'umask ' . $args->[0][0]->content . ' leaves new files world-writable (CWE-732); use 022 or 077'
        );
    }
    return;
}

# A decimal mode such as `chmod 777, $f` is read as the octal mode it was
# meant to be (B010 reports the missing zero).
sub _number ($elem) {
    return oct( $elem->content ) if defined decimal_mode($elem);
    return undef unless $elem->isa('PPI::Token::Number') && $elem->can('literal');
    return $elem->literal;
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
constant mask that does not mask other-write. There is no fix.

=cut
