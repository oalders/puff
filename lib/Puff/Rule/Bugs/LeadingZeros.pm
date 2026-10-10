package Puff::Rule::Bugs::LeadingZeros;

use v5.36;
use parent 'Puff::Rule';

use Puff::PPIUtil qw( mode_call );

sub code       {'B003'}
sub summary    {'Number with a leading zero is octal'}
sub applies_to {'PPI::Token::Number::Octal'}
sub fix_safety {'safe'}
sub options    { { strict => 0 } }

sub explanation {
    return <<~'END';
        Perl reads a number that starts with `0` as octal:

            my $count = 010;    # 8, not 10

        Padding a decimal number with zeros is a common slip. When octal is
        what you mean, `oct('10')` says so.

        The rule reports a number literal with one or more leading zeros
        followed by another digit, such as `010` or `0_755`. `0` and `00`
        are not reported. Permission modes are octal by convention, so the
        rule does not report the mode argument of `chmod`, `umask`,
        `mkdir`, `mkfifo`, `POSIX::mkfifo`, `dbmopen`, `sysopen` and
        `mkpath`, the argument of a `->chmod(0755)` method call (Path::Tiny),
        the `mask` value in an options hash passed to `make_path`, `mkpath`
        or a `->mkdir`/`->mkpath` method, or a number after a fat comma whose
        key mentions `mode` or `perm` or is `chmod` (`mode => 0755`, as
        `make_path` takes). These are the positions where B010 adds the
        leading zero to a decimal mode, so its fix is not reported. Nor does
        it report an operand of a bitwise operator, as in `$mode & 07777`
        or `0666 & ~$umask`, where octal is the norm.

        The fix replaces the literal with an `oct()` call of the same value,
        so `010` becomes `oct('010')` and `-0644` becomes `-oct('0644')`. It
        is safe: Perl folds both to the same constant. Literals with an 8
        or 9 in them do not compile and are not fixed.

        Option `strict` (default `false`): report leading zeros in
        permission modes and bit masks too.
        END
}

sub check ( $self, $elem, $doc ) {
    return unless $elem->content =~ /\A[+-]?(?:0+_*)+[1-9]/;
    return
        if !$self->option('strict') && ( defined mode_call($elem) || _is_mode_value($elem) || _is_bit_operand($elem) );
    return $self->violation(
        $elem,
        message => 'Number '
            . $elem->content
            . ' has a leading zero, so it is octal; write '
            . ( _oct_call($elem) // 'it in decimal' ),
        fixable => defined _oct_call($elem) ? 1 : 0,
    );
}

sub fix ( $self, $violation, $fix ) {
    my $call = _oct_call( $violation->element ) // return 0;
    $fix->replace( $violation->element, $call );
    return 1;
}

# 010 => oct('010'); undef for a literal that is not valid octal.
sub _oct_call ($elem) {
    my ( $sign, $digits ) = $elem->content =~ /\A([+-]?)([0-9_]+)\z/ or return;
    return if $digits =~ /[89]/;
    $sign = q{} if $sign eq q{+};
    return "${sign}oct('$digits')";
}

# mode => 0755, perms => 0600
sub _is_mode_value ($elem) {
    my $op = $elem->sprevious_sibling or return 0;
    return 0 unless $op->isa('PPI::Token::Operator') && $op->content eq '=>';
    my $key  = $op->sprevious_sibling or return 0;
    my $name = $key->isa('PPI::Token::Quote') ? $key->string : $key->content;
    return $name =~ /mode|perm|chmod/i;
}

# 0666 &~ $umask, $mode & 07777: octal is the norm for bit masks.
my %BIT_OP = map { $_ => 1 } qw( & | ^ ~ &= |= ^= );

sub _is_bit_operand ($elem) {
    my ( $prev, $next ) = ( $elem->sprevious_sibling, $elem->snext_sibling );
    return 1 if $prev && $prev->isa('PPI::Token::Operator') && $BIT_OP{ $prev->content };
    return $next && $next->isa('PPI::Token::Operator') && $BIT_OP{ $next->content } ? 1 : 0;
}

1;

# ABSTRACT: B003 - number with a leading zero is octal

__END__

=pod

=head1 DESCRIPTION

Reports a number literal with a leading zero, which Perl reads as octal,
outside the permission-mode argument of C<chmod>, C<mkdir> and friends. The
safe fix rewrites it as an C<oct()> call with the same value.

Based on L<Perl::Critic::Policy::ValuesAndExpressions::ProhibitLeadingZeros>,
extended to C<mkpath>, C<< mode => ... >> pairs and bit-mask operands.

Selected by default, as part of C<B>.

=cut
