package Puff::Rule::Bugs::AggregateAssignRef;

use v5.36;
use parent 'Puff::Rule';

use Puff::PPIUtil qw( call_args is_builtin_call );

sub code       {'B002'}
sub summary    {'Array or hash assigned a [...] or {...} reference'}
sub applies_to {'PPI::Token::Operator'}
sub fix_safety {'unsafe'}

sub explanation {
    return <<~'END';
        `[...]` and `{...}` build a single reference, not a list:

            my @names = [ 'ann', 'bob' ];    # one element, an arrayref
            my %ages  = { ann => 3 };        # warns; one key, a stringified ref

        This is almost always a typo for `( ... )`. When one reference is
        what you want, wrap it in parens so the reader can tell:
        `my @rows = ( [ 1, 2 ] );`.

        The rule reports `=` when the left side is an array, a hash, a
        dereferenced array or hash (`@$ref`, `@{$ref}`, `$ref->@*`) or a
        slice (`@a[...]`, `@h{...}`), and the whole right side starts with
        a `[...]` or `{...}` constructor. It does not report a slice with
        one scalar subscript (`@a[$i] = [...]`), which stores the reference
        in that element, or an array that `push` or `unshift` in the same
        block also gives `[...]` or `{...}` rows, which is an array of
        references.

        The fix replaces the brackets or braces with parens, so the list
        is assigned. That changes what the code does, so it is unsafe, and
        it is offered only when the constructor is the whole right side.
        If you meant the reference, wrap it in parens instead.
        END
}

my %MODIFIER = map { $_ => 1 } qw( if unless while until for foreach );

sub check ( $self, $elem, $doc ) {
    return unless $elem->content eq '=';
    my $rhs = $elem->snext_sibling or return;
    return unless $rhs->isa('PPI::Structure::Constructor');
    my $target = _list_target($elem) // return;
    return if $target eq 'Slice' && _one_element( $elem->sprevious_sibling );
    return if $target eq 'Array' && _has_ref_rows( $elem->sprevious_sibling );
    my $ref = $rhs->start->content eq '[' ? '[...]' : '{...}';
    return $self->violation(
        $elem,
        message => "$target assigned a $ref reference; use ( ... ) for a list, or ( $ref ) for one reference",
        fixable => _whole_rhs($rhs) ? 1 : 0,
    );
}

sub fix ( $self, $violation, $fix ) {
    my $rhs = $violation->element->snext_sibling or return 0;
    return 0 unless $rhs->isa('PPI::Structure::Constructor') && _whole_rhs($rhs);
    my ( $start, $finish ) = ( $rhs->start, $rhs->finish );
    return 0 unless $start && $finish;
    $fix->replace( $start, '(' );
    $fix->replace( $finish, ')' );
    return 1;
}

# 'Array', 'Hash' or 'Slice' if the left side of the = at $op is a list
# target, else undef.
sub _list_target ($op) {
    my $prev  = $op->sprevious_sibling or return;
    my $slice = 0;
    while ($prev->isa('PPI::Structure::Subscript')
        || $prev->isa('PPI::Structure::Constructor')
        || $prev->isa('PPI::Structure::Block') ) {
        $slice = 1 unless $prev->isa('PPI::Structure::Block');
        $prev  = $prev->sprevious_sibling or return;
    }
    my $sigil;
    if ( $prev->isa('PPI::Token::Cast') ) {
        $sigil = $prev->content;    # @{...}, $ref->@*
    }
    elsif ( $prev->isa('PPI::Token::Symbol') ) {
        $sigil = $prev->raw_type;
        if ( $sigil eq '$' ) {      # @$ref
            my $cast = $prev->sprevious_sibling;
            $sigil = $cast && $cast->isa('PPI::Token::Cast') ? $cast->content : '$';
        }
    }
    return unless defined $sigil && $sigil =~ /\A([\@%])\*?\z/;
    return 'Slice' if $slice;
    return $1 eq '@' ? 'Array' : 'Hash';
}

# The slice subscript holds one scalar expression, so it names one element.
sub _one_element ($subscript) {
    my @stmts = $subscript->schildren;
    return 0 unless @stmts == 1;
    for my $part ( $stmts[0]->schildren ) {
        return 0 if $part->isa('PPI::Token::Operator') && $part->content =~ /\A(?:,|=>|\.\.)\z/;
        return 0 if $part->isa('PPI::Token::Symbol')   && $part->raw_type ne '$';
        return 0 if $part->isa('PPI::Token::Cast')     && $part->content =~ /\A[\@%]/;
        return 0 if $part->isa('PPI::Token::QuoteLike::Words');
        return 0 if $part->isa('PPI::Token::Word');    # a call may return a list
        return 0 if $part->isa('PPI::Structure::List') || $part->isa('PPI::Structure::Block');
    }
    return 1;
}

# A push or unshift in the block around $sym, or in the document if there is
# none, adds a [...] or {...} row to the array $sym names.
sub _has_ref_rows ($sym) {
    return 0 unless $sym->isa('PPI::Token::Symbol') && $sym->raw_type eq '@';
    my $name  = $sym->symbol;
    my $scope = $sym->parent;
    $scope = $scope->parent until $scope->isa('PPI::Structure::Block') || !$scope->parent;
    for my $word ( @{ $scope->find('PPI::Token::Word') || [] } ) {
        next unless $word->content =~ /\A(?:push|unshift)\z/ && is_builtin_call($word);
        my ( $array, $row ) = @{ call_args($word) };
        next unless $array && $row && @$array == 1 && $row->[0]->isa('PPI::Structure::Constructor');
        return 1 if $array->[0]->isa('PPI::Token::Symbol') && $array->[0]->symbol eq $name;
    }
    return 0;
}

# The constructor is all of the right side: nothing follows it but the end
# of the statement or a statement modifier.
sub _whole_rhs ($rhs) {
    my $next = $rhs->snext_sibling or return 1;
    return 1 if $next->isa('PPI::Token::Structure') && $next->content eq ';';
    return $next->isa('PPI::Token::Word') && $MODIFIER{ $next->content };
}

1;

# ABSTRACT: B002 - array or hash assigned a [...] or {...} reference

__END__

=pod

=head1 DESCRIPTION

Reports an assignment of a C<[...]> or C<{...}> constructor to an array, a
hash, a dereferenced array or hash, or a slice, which stores one reference
where a list was probably meant. The unsafe fix turns the brackets or braces
into parens.

Based on L<Perl::Critic::Policy::ValuesAndExpressions::ProhibitArrayAssignAref>
from Perl::Critic::Pulp, extended to hashes and C<{...}>.

Selected by default, as part of C<B>.

=cut
