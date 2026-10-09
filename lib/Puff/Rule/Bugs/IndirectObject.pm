package Puff::Rule::Bugs::IndirectObject;

use v5.36;
use parent 'Puff::Rule';

use Pod::Functions ();

sub code       {'B004'}
sub summary    {'Indirect object syntax'}
sub applies_to {'PPI::Token::Word'}
sub fix_safety {'unsafe'}

sub explanation {
    return <<~'END';
        `new Foo(...)` is indirect object syntax: Perl guesses that it
        means `Foo->new(...)`. The guess depends on which subs exist when
        the line is compiled, so it can change under you. If a sub named
        `new` (or `Foo`) is in scope, the line calls that instead. Errors
        from a wrong guess are confusing, and Perl 5.36's `use v5.36`
        turns the syntax off altogether.

        The rule reports a lowercase word that is not a Perl builtin
        followed by a class name, as in `new Foo`, `new Foo::Bar(...)` or
        `create My::Thing`. A class name is a word whose last part starts
        with an uppercase letter and contains a lowercase letter, or that
        ends in `::`. ALL-CAPS words are left alone, since they are usually
        constants. `new $class` and `new $class(...)` are reported too, but
        only for `new`: `croak $message` is an ordinary function call.

        The fix rewrites the call with an arrow: `new Foo(1)` becomes
        `Foo->new(1)`, and `bootstrap Foo $VERSION;` becomes
        `Foo->bootstrap($VERSION);`. It is not offered when arguments
        without parens are followed by `or`, `and`, `xor`, `not` or a
        statement modifier. It is unsafe because the rule cannot see which
        subs are imported: when the word is really a function call (an
        imported `with Some::Role`, say), the arrow form changes what the
        code does.
        END
}

my %MODIFIER       = map { $_ => 1 } qw( if unless while until for foreach );
my %LOW_PRECEDENCE = map { $_ => 1 } qw( or and xor not );
my %UNARY          = map { $_ => 1 } ( q{-}, q{+}, q{!}, q{~}, q{\\}, q{::} );

my %KEYWORD = map { $_ => 1 } keys %Pod::Functions::Type, qw(
    if unless while until for foreach else elsif given when default
    my our local state return and or not xor
    sub package use no require do eval BEGIN END
);

sub check ( $self, $elem, $doc ) {
    my $object  = _indirect_object($elem) // return;
    my ($shape) = _call_shape($object);
    my $call    = $object->content . q{->} . $elem->content;
    $call .= q{(...)} unless defined $shape && $shape eq q{none};
    return $self->violation(
        $elem,
        message => "Indirect object syntax: write $call",
        fixable => defined $shape ? 1 : 0,
    );
}

sub fix ( $self, $violation, $fix ) {
    my $method = $violation->element;
    my $object = _indirect_object($method) // return 0;
    my ( $shape, $last ) = _call_shape($object);
    return 0 unless defined $shape;
    my $src  = $fix->source;
    my $call = $object->content . q{->} . $method->content;
    if ( $shape eq q{bare} ) {
        my $first = $object->snext_sibling;
        $fix->replace_range( $src->start_of($method), $src->start_of($first), "$call(" );
        $fix->insert_after( $last, q{)} );
        return 1;
    }
    $fix->replace_range( $src->start_of($method), $src->end_of($object), $call );
    return 1;
}

# The class word or $variable that $method is called on, or undef.
sub _indirect_object ($method) {
    my $name = $method->content;
    return unless $name =~ /\A[a-z_][a-z0-9_]*\z/ && !$KEYWORD{$name};
    my $stmt = $method->statement;
    return
           if !$stmt
        || $stmt->isa('PPI::Statement::Include')
        || $stmt->isa('PPI::Statement::Package')
        || $stmt->isa('PPI::Statement::Sub');
    my $prev = $method->sprevious_sibling;
    return if $prev && ( $prev->content eq '->' || $prev->content eq '&' );
    my $object = $method->snext_sibling or return;
    my $after  = $object->snext_sibling;
    return if $after && $after->isa('PPI::Token::Operator') && ( $after->content eq '->' || $after->content eq '=>' );

    if ( $object->isa('PPI::Token::Word') ) {
        return _is_class_name( $object->content ) ? $object : undef;
    }
    if ( $object->isa('PPI::Token::Symbol') && $name eq 'new' ) {
        return $object->raw_type eq '$' && $object->content =~ /\A\$\w+(?:::\w+)*\z/ ? $object : undef;
    }
    return;
}

sub _is_class_name ($word) {
    return 1 if $word =~ /\A[A-Za-z_]\w*(?:::\w+)*::\z/;
    my ($last) = $word =~ /(?:\A|::)(\w+)\z/ or return 0;
    return $last =~ /\A[A-Z]/ && $last =~ /[a-z]/ ? 1 : 0;
}

# How the call can be rewritten: ('none') for `new Foo`, ('list') for
# `new Foo(...)`, ('bare', $last) for `new Foo ARGS` running to the end of
# the statement, or () when it cannot.
sub _call_shape ($object) {
    my $after = $object->snext_sibling or return ('none');
    return ('list') if $after->isa('PPI::Structure::List');
    return ('none') if _ends_call($after);
    my $last;
    for ( my $el = $after ; $el ; $el = $el->snext_sibling ) {
        last if $el->isa('PPI::Token::Structure')  && $el->content eq q{;};
        return if $el->isa('PPI::Token::Operator') && $LOW_PRECEDENCE{ $el->content };
        return if $el->isa('PPI::Token::Word')     && $MODIFIER{ $el->content };
        return if $el->isa('PPI::Token::HereDoc');
        $last = $el;
    }
    return ( 'bare', $last );
}

sub _ends_call ($el) {
    return 1 if $el->isa('PPI::Token::Structure');
    return 1 if $el->isa('PPI::Token::Operator') && !$UNARY{ $el->content };
    return $el->isa('PPI::Token::Word') && $MODIFIER{ $el->content };
}

1;

# ABSTRACT: B004 - indirect object syntax

__END__

=pod

=head1 DESCRIPTION

Reports indirect object syntax such as C<new Foo(...)>, where a method name
comes before the class. The unsafe fix rewrites it as C<< Foo->new(...) >>.

Based on L<Perl::Critic::Policy::Dynamic::NoIndirect>, which compiles the
code under L<indirect>; this rule reads the source instead, so it sees only
the common forms.

Selected by default, as part of C<B>.

=cut
