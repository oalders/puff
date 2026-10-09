package Puff::Rule::Bugs::UnusedVariable;

use v5.36;
use parent 'Puff::Rule';

use Puff::PPIUtil qw( is_builtin_call );
use Scalar::Util  qw( refaddr );

sub code       {'B006'}
sub summary    {'Lexical variable is declared but never used'}
sub applies_to {'PPI::Statement::Variable'}
sub fix_safety {'unsafe'}

sub options {
    return {
        'allow-unused-subroutine-arguments' => 1,
        'allow-if-computed-by'              => [qw( Scope::Guard guard scope_guard txn_scope_guard )],
    };
}

sub explanation {
    return <<~'END';
        A `my` or `state` variable that is never used after it is declared
        is dead code at best. More often it is a leftover from a refactor,
        or a sign that the code uses a different variable than the author
        meant:

            my $total = 0;
            for my $item (@items) { $sum += $item->price }
            return $sum;

        The rule reports a variable declared by a `my` or `state` statement
        that is not mentioned anywhere after that statement in the same
        scope. A mention counts wherever it is: an element such as `$x[0]`
        or `@h{...}` counts for `@x` or `%h`, and so does interpolation into
        a string, regex, heredoc or `s///e` replacement. Declarations
        inside a condition or expression (`if ( my $x = ... )`) and loop
        variables are not checked.

        In a list, an unused variable can be replaced with `undef`:

            my ( undef, $name ) = split /:/, $line;

        The fix makes that change for a list assigned from a builtin such
        as `split`, from `@_` or from a regex match, and deletes a
        declaration without an assignment (`my $x;`) when none of its
        variables is used. Values from other calls are left alone, since
        they may be objects that do their work when destroyed, such as a
        temporary directory or a lock. An unused `my $x = EXPR;` is not
        fixed either, since EXPR may matter. The fix is unsafe because the rule cannot see uses
        that only exist at runtime, such as code in a single-quoted string
        passed to `eval`.

        Option `allow-unused-subroutine-arguments` (default `true`): do not
        report variables assigned from `@_`, `shift`, `pop` or `$_[N]`, as
        in `my ( $self, $c ) = @_;`. Set it to `false` to report them.

        Option `allow-if-computed-by` (default `["Scope::Guard", "guard",
        "scope_guard", "txn_scope_guard"]`): functions, methods and classes
        whose result is kept for its side effects, such as a guard object
        that does its work when it goes out of scope. A variable assigned
        from a call to one of these (`guard { ... }`, `$schema->txn_scope_guard`
        or `Scope::Guard->new(...)`) is not reported.
        END
}

sub check ( $self, $elem, $doc ) {
    my @vars = _declared($elem) or return;
    return if $self->option('allow-unused-subroutine-arguments') && _from_arguments($elem);
    return if $self->_computed_by_allowed($elem);
    my @unused  = $self->_unused( $elem, $doc, @vars ) or return;
    my $fixable = _fix_kind( $elem, \@vars, \@unused );
    return map {
        $self->violation(
            $_,
            message => 'Variable ' . $_->symbol . ' is declared but never used',
            fixable => defined _fix_for( $_, $fixable ) ? 1 : 0,
        )
    } @unused;
}

sub fix ( $self, $violation, $fix ) {
    my $var    = $violation->element;
    my $stmt   = _declaration($var) // return 0;
    my @vars   = _declared($stmt)                           or return 0;
    my @unused = $self->_unused( $stmt, $stmt->top, @vars ) or return 0;
    my $what   = _fix_for( $var, _fix_kind( $stmt, \@vars, \@unused ) ) // return 0;
    if ( $what eq 'delete' ) {
        _delete_statement( $fix, $stmt );
    }
    else {
        $fix->replace( $var, 'undef' );
    }
    return 1;
}

# Deletes $stmt, with its whole line when nothing else is on it.
sub _delete_statement ( $fix, $stmt ) {
    my $src   = $fix->source;
    my $text  = $src->text;
    my $start = $src->start_of($stmt);
    my $end   = $src->end_of($stmt);
    my $from  = rindex( $text, "\n", $start - 1 ) + 1;
    my $to    = index( $text, "\n", $end );
    if (   $to >= 0
        && substr( $text, $from, $start - $from ) =~ /\A[ \t]*\z/
        && substr( $text, $end, $to - $end )      =~ /\A[ \t]*\z/ ) {
        $fix->replace_range( $from, $to + 1, q{} );
        return;
    }
    $fix->delete($stmt);
    return;
}

# The my/state statement that declares $var.
sub _declaration ($var) {
    for ( my $el = $var->parent ; $el ; $el = $el->parent ) {
        return $el if $el->isa(q{PPI::Statement::Variable});
    }
    return;
}

# The variable tokens of `my $x` or `my ( $x, @y )`, or () when the
# statement is not a plain my/state declaration.
sub _declared ($stmt) {
    my $type = $stmt->type // return;
    return unless $type eq 'my' || $type eq 'state';
    my $what = $stmt->schild(1) or return;
    return $what if $what->isa('PPI::Token::Symbol');
    return unless $what->isa('PPI::Structure::List');
    my @vars;
    for my $expr ( $what->schildren ) {
        push @vars, grep { $_->isa('PPI::Token::Symbol') } $expr->schildren;
    }
    return @vars;
}

# The tokens of @vars that are not mentioned after $stmt in its scope.
sub _unused ( $self, $stmt, $doc, @vars ) {
    my $scope = $stmt->parent or return;
    return unless $scope->isa('PPI::Structure::Block') || $scope->isa('PPI::Document');
    my $index = $self->_index($doc);
    my $from  = $index->{position}{ refaddr( $stmt->last_token ) };
    my $to    = $index->{position}{ refaddr( $scope->last_token ) };
    return unless defined $from && defined $to;
    return grep {
        my $uses = $index->{uses}{ $_->symbol } || [];
        !grep { $_ > $from && $_ <= $to } @$uses;
    } @vars;
}

# 'delete' when the whole declaration can go, 'undef' when unused list
# members can be replaced with undef, undef otherwise.
sub _fix_kind ( $stmt, $vars, $unused ) {
    my @rest = map { $_->content } grep { !$_->isa('PPI::Token::Whitespace') } $stmt->schildren;
    my $list = $stmt->schild(1)->isa('PPI::Structure::List');
    if ( @rest == 3 && $rest[2] eq q{;} ) {
        return @$unused == @$vars ? 'delete' : undef;
    }
    my $op = $stmt->schild(2);
    return unless $list && $op && $op->isa('PPI::Token::Operator') && $op->content eq q{=};
    return _plain_values($stmt) ? 'undef' : undef;
}

# Builtins whose results are new plain values or still referenced elsewhere.
my %PLAIN_BUILTIN = map { $_ => 1 } qw(
    split unpack localtime gmtime caller stat lstat times each keys values sort reverse
    getpwnam getpwuid getgrnam getgrgid getpwent getgrent gethostbyname getservbyname
);

# Whether the right-hand side of $stmt yields plain values: a call to one of
# those builtins, @_ or a regex match. A value from anything else may be an
# object that does its work when it is destroyed, and dropping it early would
# change that.
sub _plain_values ($stmt) {
    my @rhs = $stmt->schildren;
    splice @rhs, 0, 3;
    my $first = $rhs[0] or return 0;
    return 1 if $first->isa(q{PPI::Token::Magic}) && $first->content eq q{@_};
    return 1 if $first->isa(q{PPI::Token::Regexp::Match});
    return 1
        if $first->isa(q{PPI::Token::Word})
        && $PLAIN_BUILTIN{ $first->content =~ s/\ACORE:://r }
        && is_builtin_call($first);
    my $op = $rhs[1];
    return
           $op
        && $op->isa(q{PPI::Token::Operator})
        && $op->content eq q{=~}
        && $rhs[2]
        && $rhs[2]->isa(q{PPI::Token::Regexp::Match}) ? 1 : 0;
}

# What the fix does for one unused variable.
sub _fix_for ( $var, $kind ) {
    return unless defined $kind;
    return $kind if $kind eq 'delete';

    # An array or hash takes everything after it; only the last one can
    # become undef without shifting the values that follow.
    return 'undef' if $var->raw_type eq q{$};
    my $next = $var->snext_sibling;
    return $next ? undef : 'undef';
}

# my ( $self, %args ) = @_;  my $self = shift;  my $x = $_[0];
sub _from_arguments ($stmt) {
    my @parts = $stmt->schildren;
    return 0 unless @parts >= 4 && $parts[2]->isa('PPI::Token::Operator') && $parts[2]->content eq q{=};
    my @rhs = @parts[ 3 .. $#parts ];
    pop @rhs if $rhs[-1]->isa('PPI::Token::Structure') && $rhs[-1]->content eq q{;};
    my $rhs = join q{}, map { $_->content } @rhs;
    $rhs =~ s/\s+//g;
    return $rhs =~ /\A(?:\@_|(?:shift|pop)(?:\(\)|\(\@_\)|\@_)?|\$_\[\d+\])\z/ ? 1 : 0;
}

sub _computed_by_allowed ( $self, $stmt ) {
    my %allowed = map { $_ => 1 } @{ $self->option('allow-if-computed-by') };
    return 0 unless %allowed;
    my @parts = $stmt->schildren;
    return 0 unless @parts >= 4 && $parts[2]->isa('PPI::Token::Operator') && $parts[2]->content eq q{=};
    for my $part ( @parts[ 3 .. $#parts ] ) {
        return 1 if $part->isa('PPI::Token::Word') && $allowed{ $part->content };
    }
    return 0;
}

# Every mention of a variable in $doc, as symbol => [ token positions ].
sub _index ( $self, $doc ) {
    my $cache = $self->{_index_cache};
    return $cache->[1] if $cache && refaddr( $cache->[0] ) == refaddr($doc);
    my ( %position, %uses );
    my $i = 0;
    for my $token ( $doc->tokens ) {
        $position{ refaddr($token) } = ++$i;
        push @{ $uses{$_} }, $i for _mentions($token);
    }
    my $index = { position => \%position, uses => \%uses };
    $self->{_index_cache} = [ $doc, $index ];
    return $index;
}

my $INTERPOLATED = qr/[\$\@]\#?\{?\s*\^?(\w+)/;

# The symbols a token mentions. Interpolated names count for every sigil,
# since `"$x[0]"` and `"@x"` both mean @x.
sub _mentions ($token) {
    if ( $token->isa('PPI::Token::Symbol') ) {
        return $token->symbol;
    }
    if ( $token->isa('PPI::Token::ArrayIndex') ) {
        return $token->content =~ /\A\$\#(\w+)\z/ ? "\@$1" : ();
    }
    if ( $token->isa('PPI::Token::Word') ) {

        # ${name} and @{name}
        my $block = $token->parent && $token->parent->parent;
        return unless $block && $block->isa('PPI::Structure::Block');
        my $cast = $block->sprevious_sibling;
        return unless $cast && $cast->isa('PPI::Token::Cast');
        return _every_sigil( $token->content );
    }
    my $text  = _interpolated_text($token) // return;
    my %names = map { $_ => 1 } $text =~ /$INTERPOLATED/g;
    return map { _every_sigil($_) } keys %names;
}

sub _every_sigil ($name) {
    return ( "\$$name", "\@$name", "\%$name" );
}

sub _interpolated_text ($token) {
    return if $token->isa('PPI::Token::Quote::Single')    || $token->isa('PPI::Token::Quote::Literal');
    return if $token->isa('PPI::Token::QuoteLike::Words') || $token->isa('PPI::Token::Regexp::Transliterate');
    if ( $token->isa('PPI::Token::HereDoc') ) {
        return if $token->content =~ /\A<<~?\s*'/;
        return join q{}, $token->heredoc;
    }
    return $token->content
        if $token->isa('PPI::Token::Quote')
        || $token->isa('PPI::Token::QuoteLike')
        || $token->isa('PPI::Token::Regexp');
    return;
}

1;

# ABSTRACT: B006 - lexical variable is declared but never used

__END__

=pod

=head1 DESCRIPTION

Reports a C<my> or C<state> variable that is not mentioned after its
declaration in the same scope, counting interpolation into strings, regexes
and heredocs. The unsafe fix replaces an unused list member with C<undef>, or
deletes a declaration without an assignment.

Based on L<Perl::Critic::Policy::Variables::ProhibitUnusedVarsStricter>,
limited to statement-level declarations, with subroutine arguments allowed by
default.

Selected by default, as part of C<B>.

=cut
