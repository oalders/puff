package Puff::Rule::Bugs::UselessRegexModifiers;

use v5.36;
use parent 'Puff::Rule';

use Scalar::Util qw( weaken );

sub code       {'B001'}
sub summary    {'Modifiers on a match against a lone qr// object are ignored'}
sub applies_to {'PPI::Token::Regexp'}
sub fix_safety {'unsafe'}

sub explanation {
    return <<~'END';
        When the whole pattern of a match or substitution is one variable
        holding a qr// object, Perl uses that compiled pattern as it is. The
        pattern modifiers on the match are ignored:

            my $re = qr/abc/;
            $str =~ /$re/i;    # still case-sensitive

        Perl 5.8 applied them, so code written then may depend on it; since
        5.10 they do nothing and Perl does not warn.

        The rule reports the modifiers that change how a pattern compiles
        (`i`, `m`, `s`, `x`, `n`, `p`, `a`, `d`, `l` and `u`) on an
        `m//`, `//`, `s///` or `split //` whose pattern is only `$name` or
        `${name}`, when every assignment to that variable in the file is a
        qr//. `g`, `c`, `o`, `e`, `ee` and `r` work as usual and are not
        reported. Put the modifiers you meant inside the qr//:
        `qr/abc/i`.

        The fix deletes the ignored modifiers, which does not change what
        the code does. It is unsafe because the rule only sees assignments
        in this file: if the variable can hold a plain string, the modifiers
        do apply and the fix changes the match.
        END
}

my $COMPILE_FLAGS = qr/[imsxnpadlu]/;

sub check ( $self, $elem, $doc ) {
    my $flags = _useless_flags($elem) // return;
    my $name  = _sole_variable($elem) // return;
    return unless $self->_holds_qr( $name, $doc );
    return $self->violation( $elem,
        message => "Modifiers /$flags are ignored: the pattern is only $name, a qr// object; move them into the qr//" );
}

sub fix ( $self, $violation, $fix ) {
    my $elem    = $violation->element;
    my $content = $elem->content;
    my ($mods) = $content =~ /([a-z]*)\z/ or return 0;
    ( my $kept = $mods ) =~ s/$COMPILE_FLAGS//g;
    return 0 if $kept eq $mods;
    $fix->replace( $elem, substr( $content, 0, length($content) - length($mods) ) . $kept );
    return 1;
}

# The compile-time modifiers on $elem, in source order, or undef.
sub _useless_flags ($elem) {
    return unless $elem->isa('PPI::Token::Regexp::Match') || $elem->isa('PPI::Token::Regexp::Substitute');
    my ($mods) = $elem->content =~ /([a-z]*)\z/;
    my $flags = join q{}, $mods =~ /($COMPILE_FLAGS)/g;
    return length $flags ? $flags : undef;
}

# '$name' if the pattern is exactly one scalar variable, else undef.
sub _sole_variable ($elem) {
    my $match = $elem->get_match_string // return;
    return "\$$1" if $match =~ /\A\$(\w+(?:::\w+)*)\z/ || $match =~ /\A\$\{(\w+(?:::\w+)*)\}\z/;
    return;
}

sub _holds_qr ( $self, $name, $doc ) {
    unless ( $self->{qr_doc} && $self->{qr_doc} == $doc ) {
        $self->{qr_doc} = $doc;
        weaken( $self->{qr_doc} );
        $self->{qr_vars} = _qr_variables($doc);
    }
    return $self->{qr_vars}{$name};
}

# Scalars whose every assignment in the document is a lone qr//, mapped
# to 1. A scalar with any other assignment (a string, .=, a list
# assignment) maps to 0.
sub _qr_variables ($doc) {
    my %qr;
    for my $sym ( @{ $doc->find('PPI::Token::Symbol') || [] } ) {
        next unless $sym->raw_type eq '$';
        my $name = $sym->symbol;
        if ( my $is_qr = _assigned_qr($sym) ) {
            $qr{$name} //= 1 if $is_qr > 0;
            $qr{$name} = 0 if $is_qr < 0;
        }
    }
    return \%qr;
}

# 1 if $sym is assigned a lone qr//, -1 if it is assigned anything else,
# 0 if this is not an assignment to it.
sub _assigned_qr ($sym) {
    my $op = $sym->snext_sibling;
    if ( !$op ) {
        return _in_list_assignment($sym) ? -1 : 0;
    }
    return 0 unless $op->isa('PPI::Token::Operator');
    my $content = $op->content;
    my $is_assign
        = $content =~ /\A(?:\*\*|[-+*\/.%x&|^]|<<|>>|&&|\|\||\/\/)?=\z/
        || ( ( $content eq '=>' || $content eq ',' ) && _is_readonly($sym) );
    return 0 unless $is_assign;
    return -1 unless $content eq '=' || $content eq '//=' || $content eq '||=' || $content eq '=>' || $content eq ',';
    my $value = $op->snext_sibling or return -1;
    return -1 unless $value->isa('PPI::Token::QuoteLike::Regexp');
    my $after = $value->snext_sibling;
    return 1 if !$after || ( $after->isa('PPI::Token::Structure') && $after->content eq ';' );
    return 1 if $after->isa('PPI::Token::Word') && $after->content =~ /\A(?:if|unless)\z/;
    return -1;
}

# my ( $re, $x ) = ...: the symbol is inside a list that is assigned to.
sub _in_list_assignment ($sym) {
    my $expr = $sym->parent or return 0;
    my $list = $expr->isa('PPI::Structure::List') ? $expr : $expr->parent or return 0;
    return 0 unless $list->isa('PPI::Structure::List');
    my $op = $list->snext_sibling or return 0;
    return $op->isa('PPI::Token::Operator') && $op->content eq '=';
}

# Readonly my $RE => qr/.../; Readonly::Scalar my $RE, qr/.../;
sub _is_readonly ($sym) {
    my $stmt  = $sym->statement or return 0;
    my $first = $stmt->schild(0) or return 0;
    return $first->isa('PPI::Token::Word') && $first->content =~ /\AReadonly(?:::Scalar)?\z/;
}

1;

# ABSTRACT: B001 - modifiers on a match against a lone qr// object are ignored

__END__

=pod

=head1 DESCRIPTION

Reports compile-time modifiers (C</i>, C</m>, C</s>, C</x> and the like) on a
match or substitution whose whole pattern is one variable that the file only
ever assigns a C<qr//> to. Perl ignores those modifiers. The unsafe fix
deletes them.

Based on L<Perl::Critic::Policy::Bangs::ProhibitUselessRegexModifiers>, which
checks only C</m> and C</s>.

Selected by default, as part of C<B>.

=cut
