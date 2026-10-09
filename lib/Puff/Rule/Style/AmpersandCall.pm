package Puff::Rule::Style::AmpersandCall;

use v5.36;
use parent 'Puff::Rule';

use Pod::Functions ();

sub code       {'Q004'}
sub summary    {'Call a sub without the & sigil'}
sub applies_to {'PPI::Token::Symbol'}
sub fix_safety {'unsafe'}

sub explanation {
    return <<~'END';
        `&foo(...)` is the Perl 4 way to call a sub. It skips the sub's
        prototype, so arguments are not checked or coerced the way a plain
        `foo(...)` call would be. `&foo;` with no parens is worse: it
        calls `foo` with the caller's own `@_`, so `foo` can see and change
        the caller's arguments.

        The rule reports `&foo(...)` and `&foo` without parens. The fix
        removes the `&` from `&foo(...)` (and `&Foo::bar(...)`). It is
        unsafe because it changes what happens when `foo` has a prototype.
        `&foo;` is reported but not fixed: the equivalent call is
        `foo(@_)`, and whether the callee should see `@_` is for you to
        decide. A sub whose name is also a Perl builtin or keyword, as in
        `&print(...)` or `&open(...)`, is reported but not fixed either,
        since there the `&` is what makes Perl call your sub.

        Uses of `&` that do not call the sub are left alone: `\&foo`,
        `\(&foo)`, `goto &foo`, `defined &foo`, `exists &foo`, `undef &foo`
        and `sort &foo`, as are `&$code(...)`, `&{...}(...)` and `&CORE::...`
        subs. An `&` that could be the bitwise operator, as in `$x &foo`, is
        not reported. `print &foo (...)` with a space before the paren is
        not fixed, because `print foo (...)` can read `foo` as a filehandle.

        This rule is not selected by default. Turn it on with `--select Q` or
        `extend-select = ["Q"]`.
        END
}

# Words before `&foo` that take `&foo` as a code ref rather than a call.
my %NOT_A_CALL = map { $_ => 1 } qw( defined exists goto undef sort );

# Words that are followed by an expression, so `word &foo` is a call and
# not the bitwise `&`.
my %TAKES_EXPR = map { $_ => 1 } qw(
    return and or not xor if unless while until elsif
    print printf say die warn push unshift join scalar ref
);

my %PRINT = map { $_ => 1 } qw( print printf say );

# Names that a bare `name(...)` would not call as a user sub.
my %BUILTIN = map { $_ => 1 } keys %Pod::Functions::Type, qw(
    if unless while until for foreach else elsif given when default
    try catch finally defer
    my our local state return and or not xor x lt gt le ge eq ne cmp
    q qq qw qr m s tr y sub package use no require do eval format
    BEGIN END INIT CHECK UNITCHECK AUTOLOAD DESTROY
    __FILE__ __LINE__ __PACKAGE__ __SUB__ __DATA__ __END__
);

sub check ( $self, $elem, $doc ) {
    my $name = _called_name($elem) // return;
    my $args = _args($elem);
    unless ($args) {
        return $self->violation(
            $elem,
            message => "&$name without parens passes the caller's \@_ along; write $name(\@_) or $name()",
            fixable => 0,
        );
    }
    if ( _clashes($name) ) {
        return $self->violation(
            $elem,
            message => "&$name(...) calls a sub named like a builtin; rename the sub",
            fixable => 0,
        );
    }
    return $self->violation(
        $elem,
        message => "Call $name(...) without the &",
        fixable => _filehandle_risk($elem) ? 0 : 1,
    );
}

sub fix ( $self, $violation, $fix ) {
    my $elem = $violation->element;
    my $name = _called_name($elem) // return 0;
    return 0 if !_args($elem) || _clashes($name) || _filehandle_risk($elem);
    $fix->replace( $elem, $name );
    return 1;
}

# The sub name in a `&name` call, or undef when $elem is not one.
sub _called_name ($elem) {
    my ($name) = $elem->content =~ /\A&((?:::)?\w+(?:::\w+)*)\z/ or return;
    return if $name =~ /\A(?:::)?CORE::/;

    my $prev = $elem->sprevious_sibling;
    if ($prev) {
        return unless _starts_term($prev);
    }
    else {
        return unless _in_call_list($elem);
    }
    return $name;
}

# True when $prev is followed by a term, so a `&` after it is a sigil.
sub _starts_term ($prev) {
    if ( $prev->isa('PPI::Token::Operator') ) {
        my $op = $prev->content;
        return $op ne '++' && $op ne '--' && $op ne '->';
    }
    return $prev->isa('PPI::Token::Word') && $TAKES_EXPR{ $prev->content };
}

# False when $elem is in a list that makes it a code ref: `\(&foo)`,
# `defined(&foo)` and the like.
sub _in_call_list ($elem) {
    my $stmt = $elem->parent or return 1;
    my $list = $stmt->parent;
    return 1 unless $list && $list->isa('PPI::Structure::List');
    my $before = $list->sprevious_sibling or return 1;
    return 0 if $before->isa('PPI::Token::Cast');
    return !( $before->isa('PPI::Token::Word') && $NOT_A_CALL{ $before->content } );
}

# The argument list right after `&name`, or undef.
sub _args ($elem) {
    my $next = $elem->snext_sibling or return;
    return $next->isa('PPI::Structure::List') ? $next : undef;
}

# `print foo (1)` reads foo as a filehandle when foo is declared later.
sub _filehandle_risk ($elem) {
    my $prev = $elem->sprevious_sibling or return 0;
    return 0 unless $prev->isa('PPI::Token::Word') && $PRINT{ $prev->content };
    return !$elem->next_sibling->isa('PPI::Structure::List');
}

sub _clashes ($name) {
    return $name !~ /::/ && $BUILTIN{$name};
}

1;

# ABSTRACT: Q004 - call a sub without the & sigil

__END__

=pod

=head1 DESCRIPTION

Reports C<&foo(...)> and C<&foo> calls. C<&foo(...)> skips the sub's
prototype, and C<&foo> without parens passes the caller's C<@_> along.

The unsafe fix removes the C<&> from C<&foo(...)> and C<&Foo::bar(...)>;
it changes behaviour when the sub has a prototype. C<&foo> without parens
is reported but not fixed, since the equivalent call is C<foo(@_)>. A sub
named like a Perl builtin or keyword (C<&print(...)>, C<&open(...)>) is
reported but not fixed, because there the C<&> is needed to call the user
sub.

Not reported: C<\&foo>, C<\(&foo)>, C<goto &foo>, C<defined &foo>,
C<defined(&foo)>, C<exists &foo>, C<undef &foo>, C<sort &foo>,
C<&$code(...)>, C<&{...}(...)>, C<&CORE::...>, and any C<&> that could be
the bitwise operator (C<$x &foo>). When the word before C<&foo> is not one
the rule knows takes an expression, it is not reported.

Not selected by default; select it with C<Q> or C<Q004>.

=cut
