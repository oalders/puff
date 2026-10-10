package Puff::Rule::Test::OkCompare;

use v5.36;
use parent 'Puff::Rule';

use Puff::PPIUtil qw( call_args is_builtin_call );
use Scalar::Util  qw( weaken );

# Test modules whose default exports include is (and isnt), and whether
# their is() compares exactly like eq. Test2's is() compares references
# deeply and treats some expected values as checks, so only Test::More's
# (and Test::Most's, which is Test::More's) counts as an exact match.
my %PROVIDER = (
    'Test::More'                   => { exports => [qw( is isnt )], like_eq => 1, import_key => 1 },
    'Test::Most'                   => { exports => [qw( is isnt )], like_eq => 1, import_key => 1 },
    'Test2::V0'                    => { exports => [qw( is isnt )] },
    'Test2::Bundle::Extended'      => { exports => [qw( is isnt )] },
    'Test2::Bundle::More'          => { exports => [qw( is isnt )] },
    'Test2::Tools::ClassicCompare' => { exports => [qw( is isnt )] },
    'Test2::Tools::Compare'        => { exports => ['is'] },
);

my %FUNC     = ( 'eq' => 'is', '==' => 'is', 'ne' => 'isnt', '!=' => 'isnt' );
my %EQUALITY = map { $_ => 1 } qw( == != eq ne <=> cmp ~~ );

# Operators that bind more tightly than == and eq, so an operand made of
# them stays one argument when the comparison becomes a comma.
my %TIGHTER = map { $_ => 1 } qw( -> ++ -- ** ! ~ \ + - =~ !~ * / % x . << >> < > <= >= lt gt le ge isa );

# Named unary operators: they take one argument and bind more tightly than
# == and eq, so `length $x == 3` is `length($x) == 3`.
my %NAMED_UNARY = map { $_ => 1 } qw( defined ref scalar length lc uc lcfirst ucfirst int abs hex oct chr ord );
my %TERM_WORD   = map { $_ => 1 } qw( __PACKAGE__ __FILE__ __LINE__ __SUB__ );

sub code       {'T001'}
sub summary    {'Use is/isnt instead of ok with eq, ==, ne or !='}
sub applies_to {'PPI::Token::Word'}
sub fix_safety {'unsafe'}

sub explanation {
    return <<~'END';
        When `ok($got eq $expected, $name)` fails, all the test output says
        is that it failed. `is($got, $expected, $name)` also prints both
        values, which is usually all you need to see what went wrong.

        The rule is declared unsafe overall, but the fix for `eq` with
        Test::More or Test::Most is safe; the fixes for `==`, `ne`, `!=` and
        for Test2 modules are unsafe.

        The rule reports `ok` whose first argument is exactly `A eq B`,
        `A == B`, `A ne B` or `A != B`, with or without a test name, when the
        file imports `is` (or `isnt`) from Test::More, Test::Most, Test2::V0,
        Test2::Bundle::Extended, Test2::Bundle::More,
        Test2::Tools::ClassicCompare or Test2::Tools::Compare (which exports
        `isnt` only when asked) into the same package, before the call. An
        explicit import list must include the function. Test::Simple exports
        only `ok`, so it does not count.

        It is not reported when an operand holds an operator that binds more
        loosely than the comparison (`ok($a == $b && $c)`, `or`, `?:`,
        assignment), when there is more than one comparison, when an operand
        has a bareword that could be a list operator (`ok(foo $x eq 'y')`),
        when the file defines its own `ok`, `is` or `isnt`, or for a method
        call such as `$tb->ok(...)`. It is also not reported for a statement
        such as `ok($x eq $y), 'name';`, where a comma follows the closing
        parenthesis: the name never reaches `ok`, which is likely a bug in
        the test. Inside a list, as in `(ok($x eq $y), 'g')`, the comma just
        separates items, so that call is reported.

        The fix rewrites `ok(A eq B, ...)` as `is(A, B, ...)` and
        `ok(A ne B, ...)` as `isnt(A, B, ...)`. Changing `eq` to Test::More's
        `is` is safe: it compares with `eq` too. The one difference is undef:
        `ok(undef eq '')` passes (with a warning) but `is(undef, '')` fails.
        That test was hiding a bug, so the fix is still classed safe.
        Everything else is unsafe:

        - `==` and `!=` compare numbers, `is` and `isnt` compare strings, so
          `ok(1.0 == "1.00")` passes and `is(1.0, "1.00")` fails;
        - Test::More's `isnt` passes `isnt(undef, '')`, which `ne` failed;
        - Test2's `is` compares references deeply and treats a regex or a
          check as a pattern, not a string.

        No fix is offered when `ok` has more than two arguments, when an
        operand is an array, a hash or a parenthesized list, or when a
        comment sits next to the operator. Test2's `is` has no prototype, so
        `@a` would be flattened into its elements; the fix is declined for
        every module to keep it simple.
        END
}

sub check ( $self, $elem, $doc ) {
    return unless $elem->content eq 'ok' && is_builtin_call($elem);
    my $facts = $self->_doc_facts($doc);
    return if $facts->{local}{ok};

    return if _name_outside_call($elem);

    my $args  = call_args($elem);
    my $parts = _split_compare( $args->[0] // [] ) or return;
    my $op    = $parts->{op}->content;
    my $func  = $FUNC{$op};
    return if $facts->{local}{$func};
    my $like_eq = _provider( $facts, $elem, $func ) // return;

    return $self->violation(
        $elem,
        message    => "ok(... $op ...) only says that it failed; use $func(), which shows both values",
        fixable    => @$args <= 2 && _fixable_operands($parts) ? 1      : 0,
        fix_safety => $op eq 'eq' && $like_eq                  ? 'safe' : 'unsafe',
    );
}

sub fix ( $self, $violation, $fix ) {
    my $elem  = $violation->element;
    my $parts = _split_compare( call_args($elem)->[0] // [] ) or return 0;
    my $src   = $fix->source;
    my $from  = $src->end_of( $parts->{lhs}[-1] );
    my $to    = $src->start_of( $parts->{rhs}[0] );

    # Only whitespace may surround the operator: a comment there would
    # swallow the comma.
    return 0 unless substr( $src->text, $from, $to - $from ) =~ /\A\s*(?:==|!=|eq|ne)\s*\z/;
    $fix->replace( $elem, $FUNC{ $parts->{op}->content } );
    $fix->replace_range( $from, $to, ', ' );
    return 1;
}

my %EXPR_BLOCK = map { $_ => 1 } qw( map grep sort do );

# True for a statement such as `ok($x eq $y), 'name';`: the name never
# reaches ok(), so the call is likely a bug in the test, not something to
# rewrite. Only a plain statement that starts with ok counts. Inside a list
# (`(ok($x eq $y), 'g')`), after `return` or as the value of a map, grep,
# sort or do block, the comma separates list items and the fix is fine.
sub _name_outside_call ($elem) {
    my $stmt = $elem->parent;
    return 0 unless ref $stmt eq 'PPI::Statement' && $stmt->schild(0) == $elem;
    my $block = $stmt->parent;
    if ( $block && $block->isa('PPI::Structure::Block') ) {
        my $word = $block->sprevious_sibling;
        return 0 if $word && $word->isa('PPI::Token::Word') && $EXPR_BLOCK{ $word->content };
    }
    my $list = $elem->snext_sibling;
    return 0 unless $list && $list->isa('PPI::Structure::List');
    my $after = $list->snext_sibling;
    return $after && $after->isa('PPI::Token::Operator') && $after->content =~ /\A(?:,|=>)\z/ ? 1 : 0;
}

# { lhs => [...], op => $token, rhs => [...] } when the elements are exactly
# A op B with op one of eq, ==, ne, !=, else nothing.
sub _split_compare ($elems) {
    my @at = grep { $elems->[$_]->isa('PPI::Token::Operator') && $EQUALITY{ $elems->[$_]->content } } 0 .. $#$elems;
    return unless @at == 1;
    my $i = $at[0];
    return unless $FUNC{ $elems->[$i]->content } && $i > 0 && $i < $#$elems;
    my @lhs = @$elems[ 0 .. $i - 1 ];
    my @rhs = @$elems[ $i + 1 .. $#$elems ];
    return unless _simple_operand( \@lhs ) && _simple_operand( \@rhs );
    return { lhs => \@lhs, op => $elems->[$i], rhs => \@rhs };
}

# Every operator binds more tightly than ==, and every bareword is a
# function call with parens, a method or class name, or a named unary
# operator.
sub _simple_operand ($side) {
    for my $j ( 0 .. $#$side ) {
        my $el = $side->[$j];
        if ( $el->isa('PPI::Token::Operator') ) {
            return 0 unless $TIGHTER{ $el->content };
        }
        elsif ( $el->isa('PPI::Token::Word') ) {
            my $word = $el->content;
            next if $NAMED_UNARY{$word} || $TERM_WORD{$word};
            my $prev = $j > 0 ? $side->[ $j - 1 ] : undef;
            my $next = $side->[ $j + 1 ];
            next if $prev && $prev->isa('PPI::Token::Operator') && $prev->content eq '->';
            next if $next && $next->isa('PPI::Structure::List');
            next if $next && $next->isa('PPI::Token::Operator') && $next->content eq '->';
            return 0;
        }
        elsif ( $el->isa('PPI::Structure::Block') ) {
            return 0 unless $j > 0 && $side->[ $j - 1 ]->isa('PPI::Token::Cast');    # @{...}
        }
    }
    return 1;
}

# No array, hash or bare parenthesized list at the top of either operand,
# and nothing but whitespace around the operator. Test2's is() has no
# prototype, so @a would be flattened; declined for every module to keep it
# simple.
sub _fixable_operands ($parts) {
    for (
        my $tok = $parts->{lhs}[-1]->last_token->next_token ;
        $tok != $parts->{rhs}[0]->first_token ;
        $tok = $tok->next_token
    ) {
        return 0 unless $tok == $parts->{op} || $tok->isa('PPI::Token::Whitespace');
    }
    for my $side ( $parts->{lhs}, $parts->{rhs} ) {
        for my $j ( 0 .. $#$side ) {
            my $el = $side->[$j];
            return 0 if $el->isa('PPI::Token::Symbol') && $el->raw_type =~ /\A[\@%]\z/;
            return 0 if $el->isa('PPI::Token::Cast')   && $el->content  =~ /\A[\@%]/;
            next unless $el->isa('PPI::Structure::List');
            my $prev = $j > 0 ? $side->[ $j - 1 ] : undef;
            next if $prev && ( $prev->isa('PPI::Token::Word') || $prev->content eq '->' );
            return 0;
        }
    }
    return 1;
}

# Undef when nothing imports $func into the package of $call before it;
# else true when every module that does has an is() that compares like eq.
sub _provider ( $facts, $call, $func ) {
    my $package = $facts->{has_package} ? _package_of($call) : 'main';
    my @from = grep { $_->{package} eq $package && $_->{imports}{$func} && _before( $_->{location}, $call->location ) }
        @{ $facts->{includes} };
    return unless @from;
    return ( grep { !$_->{like_eq} } @from ) ? 0 : 1;
}

sub _before ( $x, $y ) {
    return $x->[0] < $y->[0] || ( $x->[0] == $y->[0] && $x->[1] < $y->[1] );
}

# The answers depend only on the whole document, so they are computed once
# per document. The weakened reference goes undef when the document is
# freed, so a re-parsed document never sees another document's answers.
# This relies on fixes being text edits: a document is never changed in
# place.
sub _doc_facts ( $self, $doc ) {
    unless ( $self->{facts_doc} && $self->{facts_doc} == $doc ) {
        $self->{facts_doc} = $doc;
        weaken( $self->{facts_doc} );
        my $has_package = $doc->find_first('PPI::Statement::Package') ? 1 : 0;
        $self->{facts} = {
            has_package => $has_package,
            includes    => [ _providers( $doc, $has_package ) ],
            local       => _local_subs($doc),
        };
    }
    return $self->{facts};
}

sub _providers ( $doc, $has_package ) {
    my @found;
    for my $inc ( @{ $doc->find('PPI::Statement::Include') || [] } ) {
        next unless $inc->type eq 'use';
        my $info = $PROVIDER{ $inc->module // '' } or next;
        push @found, {
            package  => $has_package ? _package_of($inc) : 'main',
            location => $inc->location,
            like_eq  => $info->{like_eq} // 0,
            imports  => _imports( $inc, $info ),
        };
    }
    return @found;
}

# The names out of is and isnt that a use statement imports.
sub _imports ( $inc, $info ) {
    my @args = $inc->arguments;
    return {} if @args == 1 && $args[0]->isa('PPI::Structure::List') && !$args[0]->schildren;    # use Foo ()

    my @names;
    if ( $info->{import_key} ) {

        # Test::More's other arguments are its plan; only import => [...]
        # lists functions.
        for my $j ( 0 .. $#args - 2 ) {
            next unless ( _string( $args[$j] ) // q{} ) eq 'import';
            next unless $args[ $j + 1 ]->isa('PPI::Token::Operator') && $args[ $j + 1 ]->content eq '=>';
            @names = _strings_in( $args[ $j + 2 ] );
            return {} unless @names;
        }
    }
    else {
        # Test2's arguments are names, -options and the values after =>.
        for my $j ( 0 .. $#args ) {
            my ( $prev, $next ) = ( $args[ $j - 1 ], $args[ $j + 1 ] );
            next if $j > 0 && $prev->isa('PPI::Token::Operator') && $prev->content eq '=>';
            next if $next  && $next->isa('PPI::Token::Operator') && $next->content eq '=>';
            push @names, grep { !/\A-/ } _strings_in( $args[$j] );
        }
    }

    my %default  = map           { $_ => 1 } @{ $info->{exports} };
    my %excluded = map           { s/\A!//r => 1 } grep {/\A!/} @names;
    my @wanted   = grep          { !/\A!/ } @names;
    my %imported = @wanted ? map { $_ eq ':DEFAULT' ? %default : ( $_ => 1 ) } @wanted : %default;
    return { map { $_ => 1 } grep { $imported{$_} && !$excluded{$_} } qw( is isnt ) };
}

sub _strings_in ($elem) {
    return $elem->literal if $elem->isa('PPI::Token::QuoteLike::Words');
    my $string = _string($elem);
    return $string if defined $string;
    return unless $elem->isa('PPI::Node');
    return
        map { $_->isa('PPI::Token::QuoteLike::Words') ? $_->literal : _string($_) // () }
        @{ $elem->find( sub { $_[1]->isa('PPI::Token::Quote') || $_[1]->isa('PPI::Token::QuoteLike::Words') } ) || [] };
}

sub _string ($elem) {
    return $elem->string if $elem->isa('PPI::Token::Quote');
    return $elem->content if $elem->isa('PPI::Token::Word');
    return;
}

# ok, is and isnt defined in the file itself (sub NAME or *NAME = ...).
sub _local_subs ($doc) {
    my %local;
    for my $sub ( @{ $doc->find('PPI::Statement::Sub') || [] } ) {
        my $name = $sub->name // next;
        $local{ $name =~ s/\A.*:://r } = 1;
    }
    for my $glob ( @{ $doc->find('PPI::Token::Symbol') || [] } ) {
        $local{$1} = 1 if $glob->content =~ /\A\*(?:.*::)?(\w+)\z/;
    }
    return \%local;
}

# The package an element is compiled in: the nearest package statement
# before it in its own or an enclosing block, or the block form around it.
sub _package_of ($elem) {
    my $node = $elem;
    while ( my $parent = $node->parent ) {
        for ( my $prev = $node->sprevious_sibling ; $prev ; $prev = $prev->sprevious_sibling ) {
            return $prev->namespace
                if $prev->isa('PPI::Statement::Package') && !grep { $_->isa('PPI::Structure::Block') } $prev->schildren;
        }
        return $parent->namespace if $parent->isa('PPI::Statement::Package');
        $node = $parent;
    }
    return 'main';
}

1;

# ABSTRACT: T001 - use is/isnt instead of ok with eq, ==, ne or !=

__END__

=pod

=head1 DESCRIPTION

Reports C<ok(A eq B)>, C<ok(A == B)>, C<ok(A ne B)> and C<ok(A != B)>,
with or without a test name and with or without parens, when C<is> (or
C<isnt>) is imported into the same package before the call. A failing
C<ok> prints only that it failed; C<is> and C<isnt> also print both values.

The modules that count are L<Test::More>, L<Test::Most>, L<Test2::V0>,
L<Test2::Bundle::Extended>, L<Test2::Bundle::More>,
L<Test2::Tools::ClassicCompare> and L<Test2::Tools::Compare> (which exports
C<isnt> only on request). L<Test::Simple> exports only C<ok>. C<use Foo ()>
imports nothing; an explicit import list (Test::More's
C<< import => [...] >>, or Test2's list of names) must name the function, and
C<!is> removes it.

=head2 Edge cases

=over

=item *

The first argument must be exactly C<A op B>. A second comparison, or any
operator that binds more loosely than C<==> (C<&&>, C<||>, C<//>, C<and>,
C<or>, C<not>, C<?:>, C<..>, assignment, bitwise C<&> and C<|>), is not
reported. Commas inside nested parens or brackets are fine; a comma at the
top level ends the first argument.

=item *

A bareword in an operand must be a call with parens, a method or class
name, a named unary operator such as C<length> or C<scalar>, or
C<__PACKAGE__>. Anything else could be a list operator that swallows the
comparison, so it is not reported.

=item *

A method call (C<< $tb->ok >>), a fully qualified C<Test::More::ok>, and
files that define their own C<ok>, C<is> or C<isnt> are not reported.

=item *

The fix rewrites C<ok> as C<is> or C<isnt> and the operator as a comma.
It is safe only for C<eq> with Test::More or Test::Most, whose C<is>
compares with C<eq>. The one difference is undef: C<ok(undef eq '')> passes
(with a warning) but C<is(undef, '')> fails, so the fix can turn a passing
test into a failing one. That test was hiding a bug, which is why the fix is
still classed safe. C<==> and C<!=> become string comparisons, Test::More's C<isnt>
treats undef as different from C<''>, and Test2's C<is> compares references
deeply, so those fixes are unsafe.

=item *

No fix is offered for C<ok> with more than two arguments, when an operand
is an array, a hash or a bare parenthesized list, or when a comment sits
next to the operator. Test::More's C<is> has a C<($$;$)> prototype, but
Test2's has none, so C<@a> would be flattened into its elements; the fix is
declined for every module to keep it simple.

=item *

An C<ok> whose first argument starts with parens (C<ok( ($x + 1) == 2 )>)
is not reported, because PPI does not parse that argument as an
expression.

=back

Not selected by default; select it with C<--select T>.

=cut
