package Puff::Rule::Bugs::ShadowedVariable;

use v5.36;
use parent 'Puff::Rule';

use Puff::LexicalScopes qw( conflicts_at );

sub code            {'B008'}
sub summary         {'Lexical variable shadows one from an enclosing scope'}
sub applies_to      { [ 'PPI::Token::Symbol', 'PPI::Token::Prototype' ] }
sub explicit_select {1}

sub explanation {
    return <<~'END';
        A declaration in an inner scope that reuses the name of a variable
        from an enclosing scope hides the outer one until the inner scope
        ends. It is easy to read the code as using the outer variable, or to
        assign to the inner one meaning to change the outer:

            my $found;
            for my $item (@items) {
                my $found = $item if $item->ok;    # the outer $found stays undef
            }

        The rule reports a `my`, `our` or `state` variable, a sub signature
        parameter, or a `catch ($e)` variable, whose name is already
        declared in an enclosing scope: an outer block, the file, a `for my $x` loop variable or a
        variable declared in an `if` or `while` condition. Sub bodies count,
        so a sub that declares `my $x` shadows a file-level `my $x` declared
        before the sub; so do anonymous subs. `my $x = $x + 1` inside a
        block reports the new `$x`, which is a classic bug when the outer
        `$x` was meant. Blocks side by side, such as two subs or two loops,
        can reuse a name. `$x`, `@x` and `%x` are different variables, and
        an inner `our` of a name an outer scope declared with `our` is not
        reported. There is no fix.

        Not selected by default, not even by `--select B`: enable it by its
        exact code (`--extend-select B008`) or with `ALL`.
        END
}

sub check ( $self, $elem, $doc ) {
    return map { $self->violation( $elem, message => "$_->{symbol} shadows the declaration on line $_->{line}" ) }
        grep { $_->{kind} eq 'shadowed' } conflicts_at( $elem, $doc );
}

1;

# ABSTRACT: B008 - lexical variable shadows one from an enclosing scope

__END__

=pod

=head1 DESCRIPTION

Reports a C<my>, C<our> or C<state> variable, a sub signature parameter, or
the variable of C<try { } catch ($e) { }>, that hides a variable of the same name declared earlier in an enclosing
scope: a C<for my $x> loop variable redeclared in the loop body, a variable
from an C<if> or C<while> condition redeclared in one of its blocks, or a
sub (named or anonymous) declaring a name the file already declared. There
is no fix.

A variable is visible only after its declaration's statement, so
C<my $x = do { my $x = 1 }> is not reported, while C<my $x = $x + 1> in an
inner block is: the new C<$x> hides the outer one, which is a common bug.
Redeclaring a signature parameter in the sub's body is reported by B007,
since both are in the body's scope. Sigils matter, C<local> is ignored, and
an inner C<our> of a name an outer scope declared with C<our> is not
reported (in the same package it names the same global). Code in string
C<eval>s is not seen.

Not selected by default, and not by the prefix C<B> either: select it by
its exact code or with C<ALL>. See L<Puff::Rule/explicit_select>.

=cut
