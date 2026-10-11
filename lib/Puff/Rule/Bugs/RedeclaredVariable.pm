package Puff::Rule::Bugs::RedeclaredVariable;

use v5.36;
use parent 'Puff::Rule';

use Puff::LexicalScopes qw( conflicts_at );

sub code            {'B007'}
sub summary         {'Lexical variable is redeclared in the same scope'}
sub applies_to      { [ 'PPI::Token::Symbol', 'PPI::Token::Prototype' ] }
sub explicit_select {1}

sub explanation {
    return <<~'END';
        Declaring the same variable twice in one scope makes the second
        declaration hide the first for the rest of the scope. Perl warns
        "masks earlier declaration in same scope", and the first variable
        can no longer be reached:

            my $total = 0;
            ...
            my $total = compute();    # the first $total is gone

        Usually the second `my` should have been a plain assignment. The
        rule reports a `my`, `our` or `state` variable declared again in
        the same scope, including in a list (`my ( $x, $y )`), in the
        conditions of one `if`/`elsif` chain, and in a sub's body when the
        sub's signature already has a parameter of that name (signature
        parameters belong to the body's scope). `$x`, `@x` and `%x` are
        different variables. `our $x` twice is reported only in the same
        package; in different packages it names different globals, as with
        `our $VERSION` in each package of a file. `local` is not a
        declaration. There is no fix.

        Not selected by default, not even by `--select B`: enable it by its
        exact code (`--extend-select B007`) or with `ALL`.
        END
}

sub check ( $self, $elem, $doc ) {
    return map {
        $self->violation(
            $elem,
            message => "$_->{symbol} is redeclared in the same scope (first declared on line $_->{line})",
        )
    } grep { $_->{kind} eq 'redeclared' } conflicts_at( $elem, $doc );
}

1;

# ABSTRACT: B007 - lexical variable is redeclared in the same scope

__END__

=pod

=head1 DESCRIPTION

Reports a C<my>, C<our> or C<state> variable declared a second time in the
same scope (Perl's "masks earlier declaration in same scope" warning), which
hides the first one for the rest of the scope. There is no fix.

Scopes are blocks, the file, and each compound statement for the variables
declared in its condition or loop header, so C<if ( my $x = ... ) { }
elsif ( my $x = ... ) { }> is reported. A sub's signature parameters belong
to its body, so C<sub f ($x) { my $x }> is reported here rather than by
B008; likewise a C<catch ($e)> variable belongs to its catch block. Sigils
matter: C<$x>, C<@x> and C<%x> are different. C<local> is ignored. Two
C<our> declarations of one name are reported only in the same package, so
C<our $VERSION> in each of two packages in one file is fine. Code in string
C<eval>s is not seen.

Not selected by default, and not by the prefix C<B> either: select it by
its exact code or with C<ALL>. See L<Puff::Rule/explicit_select>.

=cut
