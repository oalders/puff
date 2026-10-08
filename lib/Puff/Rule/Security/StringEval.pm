package Puff::Rule::Security::StringEval;

use v5.36;
use parent 'Puff::Rule';

use Puff::PPIUtil qw( is_builtin_call call_args );

# An unescaped $ or @: the string interpolates something.
my $INTERPOLATES = qr/(?<!\\)(?:\\\\)*[\$\@]/;

sub code       {'S004'}
sub summary    {'Do not eval a string built at runtime'}
sub applies_to {'PPI::Token::Word'}
sub cwe        {95}

sub explanation {
    return <<~'END';
        String eval compiles and runs its argument as Perl code. If any part
        of that string comes from outside the program, an attacker can run
        their own code (CWE-95, eval injection). Block eval, `eval { ... }`,
        only catches exceptions and is not reported.

        The rule reports `eval EXPR` unless EXPR is a single string with
        nothing interpolated in it: '...', q{...}, a "..." or qq{...} string
        with no $ or @, or a heredoc with no $ or @. A constant string, such
        as the `eval "use Foo; 1"` idiom for loading an optional module,
        cannot be injected into. `eval` with no argument evaluates $_ and is
        reported.

        There is no fix. To load a module whose name is only known at runtime,
        use Module::Runtime's require_module; to run code chosen at runtime,
        dispatch through a hash of code references.

        Ruff's equivalent is S307.
        END
}

sub check ( $self, $elem, $doc ) {
    my $name = $elem->content;
    return unless ( $name eq 'eval' || $name eq 'CORE::eval' ) && is_builtin_call($elem);

    my $next = $elem->snext_sibling;
    return if $next && $next->isa('PPI::Structure::Block');

    my $args = call_args($elem);
    return if @$args == 1 && @{ $args->[0] } == 1 && _is_constant_string( $args->[0][0] );
    return $self->violation( $elem, message => 'String eval of a runtime value (CWE-95); use block eval or a dispatch table' );
}

sub _is_constant_string ($elem) {
    return 1 if $elem->isa('PPI::Token::Quote::Single') || $elem->isa('PPI::Token::Quote::Literal');
    if ( $elem->isa('PPI::Token::Quote::Double') || $elem->isa('PPI::Token::Quote::Interpolate') ) {
        return $elem->string !~ $INTERPOLATES;
    }
    if ( $elem->isa('PPI::Token::HereDoc') ) {
        return 1 if ( $elem->{_mode} // '' ) eq 'literal';
        return join( q{}, $elem->heredoc ) !~ $INTERPOLATES;
    }
    return 0;
}

1;

# ABSTRACT: S004 - do not eval a string built at runtime

__END__

=pod

=head1 DESCRIPTION

Reports C<eval EXPR> (and C<CORE::eval EXPR>) unless EXPR is a single
constant string. Block C<eval> is not reported. There is no fix.

=cut
