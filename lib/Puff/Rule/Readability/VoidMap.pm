package Puff::Rule::Readability::VoidMap;

use v5.36;
use parent 'Puff::Rule';

my %FUNCTIONS = map { $_ => 1 } qw( map grep CORE::map CORE::grep );
my %MODIFIERS = map { $_ => 1 } qw( if unless while until for foreach );

# PPI::Statement::Compound->type for loops; `until` is reported as `while`.
my %LOOPS = map { $_ => 1 } qw( for foreach while );

sub code       {'R002'}
sub summary    {'map or grep in void context'}
sub applies_to {'PPI::Statement'}

sub explanation {
    return <<~'END';
        `map` and `grep` build a list. Calling one only for what its block
        does, and throwing the list away, hides a loop in an expression and
        builds a list for nothing. A `for` loop says what is meant:

            print for @list;          # not: map { print } @list;
            $seen{$_}++ for @list;    # not: grep { $seen{$_}++ } @list;

        Reported: a statement that is nothing but a `map` or `grep` call, in
        any form (`map BLOCK LIST`, `map EXPR, LIST`, `map(...)`), with or
        without a statement modifier such as `... if $y;`.

        Not reported: a `map` or `grep` whose value is used, by an
        assignment, as an argument, by `return`, `scalar`, a condition, an
        `or`/`and`, or any other operator; the last statement of a sub,
        `do`, `eval`, `map`, `grep`, `sort`, `if`/`else` or bare block,
        whose value may be the block's value (a sub's return value, a `do`
        block's value, the result of a `map` block);
        method calls such as `$obj->map(...)`; `map` as a hash key; and
        `&map(...)` or `Foo::map(...)`.

        The last statement of a `for`, `foreach`, `while` or `until` loop
        body is reported: a loop has no value to use.

        The last statement of a file is reported: a file's last value is
        only used by `require`, and `1;` is the usual way to provide it.

        There is no fix: whether the block's value matters, and how to write
        the loop, is a choice for a person.
        END
}

sub check ( $self, $elem, $doc ) {
    return unless ref $elem eq 'PPI::Statement';
    my $parent = $elem->parent or return;
    return unless $parent->isa('PPI::Structure::Block') || $parent->isa('PPI::Document');

    my ( $word, @rest ) = $elem->schildren;
    return unless $word && $word->isa('PPI::Token::Word') && $FUNCTIONS{ $word->content };
    return unless _void_call(@rest);

    # The last statement of a block may be the block's value, unless the
    # block is a loop body (or a loop's `continue` block), which has none.
    return if $parent->isa('PPI::Structure::Block') && !$elem->snext_sibling && !_in_loop($parent);

    my $name = $word->content =~ s/\ACORE:://r;
    return $self->violation( $word, message => "$name in void context; use a for loop", fixable => 0 );
}

sub _in_loop ($block) {
    my $stmt = $block->parent;
    return $stmt && $stmt->isa('PPI::Statement::Compound') && $LOOPS{ $stmt->type // '' };
}

# True when the tokens after the map or grep word are its arguments and
# nothing else, up to an optional statement modifier.
sub _void_call (@rest) {
    pop @rest if @rest && $rest[-1]->isa('PPI::Token::Structure') && $rest[-1]->content eq ';';
    for my $i ( 0 .. $#rest ) {
        my $tok = $rest[$i];
        last if $tok->isa('PPI::Token::Word') && $MODIFIERS{ $tok->content };
        if ( $tok->isa('PPI::Token::Operator') ) {

            # `map => 1` is a hash key, and `map ... or die` uses the value.
            return 0 if $i == 0 && $tok->content eq '=>';
            return 0 if $tok->content =~ /\A(?:or|and|xor)\z/;
        }

        # In `map(...)` the parentheses hold every argument, so anything
        # after them other than a modifier makes a larger expression.
        return 0 if $i > 0 && $rest[0]->isa('PPI::Structure::List');
    }
    return 1;
}

1;

# ABSTRACT: R002 - map or grep in void context

__END__

=pod

=head1 DESCRIPTION

Reports C<map> and C<grep> called only for the side effects of their block
or expression, with the list they build thrown away, such as
C<map { print } @list;>. A C<for> loop (C<print for @list;>) says what is
meant. There is no fix.

A call is in void context when it is the whole of a plain statement in a
block or at the top of the file: C<map BLOCK LIST>, C<map EXPR, LIST> or
C<map(...)>, optionally followed by a statement modifier (C<... if $y;>,
C<... for @z;>), which does not use the value. A label on the statement is
allowed.

Edge cases:

=over 4

=item *

The last statement of a sub, anonymous sub, C<do>, C<eval>, C<map>,
C<grep> or C<sort> block is not reported, since it may be the block's
value: a sub's return value, the value of a C<do> block, or the result of a
C<map>, C<grep> or C<sort> block. This applies to C<if>, C<unless>,
C<elsif>, C<else> and bare blocks too, since puff cannot tell whether such
a block ends a sub.

=item *

The last statement of a loop body is reported: C<for>, C<foreach> (including
C-style C<for (;;)>), C<while> and C<until> blocks and their C<continue>
blocks have no value to use.

=item *

The last statement of a file is reported. A file's last value is only used
by C<require>, and C<1;> is the usual way to provide it.

=item *

A C<map> or C<grep> whose value is used is not reported: assigned,
passed to a function, after C<return> or C<scalar>, in a condition, joined
with C<or>, C<and> or C<xor>, or followed by any operator after
C<map(...)>.

=item *

A C<map> or C<grep> that is not the last statement inside another C<map>
or C<grep> block is reported: its value is thrown away there too.

=item *

Method calls (C<< $obj->map(...) >>), C<map> as a hash key (C<{map}>,
C<< map => 1 >>), C<&map(...)>, C<Foo::map(...)>, and the word in strings,
comments and POD are not reported. C<CORE::map> and C<CORE::grep> are.

=back

Not selected by default; select it with C<--select R> or
C<extend-select = ["R"]>.

=cut
