package Puff::Rule::Readability::UnlessElse;

use v5.36;
use parent 'Puff::Rule';

sub code       {'R001'}
sub summary    {'Use if/else instead of unless/else'}
sub applies_to {'PPI::Statement::Compound'}
sub fix_safety {'safe'}

sub explanation {
    return <<~'END';
        `unless (X) { A } else { B }` is a double negative: the reader has
        to work out that B runs when X is true. `if (X) { B } else { A }`
        says the same thing directly:

            if ($ok) {
                proceed();
            }
            else {
                retry();
            }

        The fix rewrites `unless` as `if` and swaps the two blocks, braces
        and everything between them, comments included. The condition is
        not changed, so it is evaluated exactly as before, and a `my`
        declared in it is visible in both blocks either way.

        `unless ... elsif ... else` is reported, but not fixed: moving the
        first block means negating the condition or reordering the
        branches, which is better done by hand.

        The fix is not offered when there is a comment or POD between the
        first block's closing brace and the `else` block, since it is not
        clear which block it belongs to, or when the statement contains a
        heredoc, whose body would not move with its block.

        `... unless X;` with no else is not reported.
        END
}

sub check ( $self, $elem, $doc ) {
    my $parts = _parts($elem) or return;
    if ( $parts->{elsif} ) {
        return $self->violation(
            $parts->{keyword},
            message => 'Use if instead of unless with elsif and else',
            fixable => 0,
        );
    }
    return $self->violation( $parts->{keyword}, fixable => _fixable($parts) ? 1 : 0 );
}

sub fix ( $self, $violation, $fix ) {
    my $parts = _parts( $violation->element->parent ) or return 0;
    return 0 if $parts->{elsif} || !_fixable($parts);

    my $src = $fix->source;
    my ( $first, $second ) = @{$parts}{qw( first second )};
    $fix->replace_range( $src->start_of( $parts->{keyword} ), $src->end_of( $parts->{keyword} ), 'if' );
    $fix->replace_range( $src->start_of($first), $src->end_of($first), $second->content );
    $fix->replace_range( $src->start_of($second), $src->end_of($second), $first->content );
    return 1;
}

# The pieces of `unless (COND) BLOCK [elsif (COND) BLOCK ...] else BLOCK`, or
# nothing if $elem is not that.
sub _parts ($elem) {
    return unless $elem && $elem->isa('PPI::Statement::Compound');
    my @kids = $elem->schildren;
    shift @kids if @kids && $kids[0]->isa('PPI::Token::Label');
    return unless @kids >= 5;
    my ( $keyword, $cond, $first ) = @kids;
    return unless _is_word( $keyword, 'unless' );
    return unless $cond->isa('PPI::Structure::Condition') && $first->isa('PPI::Structure::Block');

    my ( $else, $second ) = @kids[ -2, -1 ];
    return unless _is_word( $else, 'else' ) && $second->isa('PPI::Structure::Block');

    my @middle = @kids[ 3 .. $#kids - 2 ];
    return unless @middle % 3 == 0;
    while ( my ( $word, $c, $b ) = splice @middle, 0, 3 ) {
        return
               unless _is_word( $word, 'elsif' )
            && $c->isa('PPI::Structure::Condition')
            && $b->isa('PPI::Structure::Block');
    }
    return {
        keyword => $keyword,
        first   => $first,
        else    => $else,
        second  => $second,
        elsif   => @kids > 5 ? 1 : 0,
    };
}

sub _is_word ( $elem, $word ) {
    return $elem->isa('PPI::Token::Word') && $elem->content eq $word;
}

# Swapping the blocks is only clear when nothing but whitespace and `else`
# separates them, and only correct when no heredoc body is tied to a line.
sub _fixable ($parts) {
    my $stmt = $parts->{keyword}->parent;
    return 0 if $stmt->find_first('PPI::Token::HereDoc');
    my $elem = $parts->{first}->next_sibling;
    while ( $elem && $elem != $parts->{second} ) {
        return 0 unless $elem->isa('PPI::Token::Whitespace') || $elem == $parts->{else};
        $elem = $elem->next_sibling;
    }
    return 1;
}

1;

# ABSTRACT: R001 - use if/else instead of unless/else

__END__

=pod

=head1 DESCRIPTION

Reports C<unless (X) { A } else { B }>, a double negative. The safe fix
rewrites it as C<if (X) { B } else { A }>: C<unless> becomes C<if> and the
two blocks, with everything inside their braces, trade places. The condition
is left as it is.

Edge cases:

=over 4

=item *

C<unless ... elsif ... else> is reported with no fix.

=item *

C<unless> with no C<else>, and the statement modifier C<... unless X;>,
are not reported.

=item *

No fix when a comment or POD sits between the first block and the C<else>
block (it is unclear which block it describes), or when the statement holds
a heredoc (its body follows the line it starts on, not its block).

=item *

A label before C<unless> stays where it is, and a C<my> in the condition is
in scope in both blocks before and after the fix.

=back

Not selected by default; select it with C<--select R>.

=cut
