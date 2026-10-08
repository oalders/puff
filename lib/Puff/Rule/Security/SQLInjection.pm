package Puff::Rule::Security::SQLInjection;

use v5.36;
use parent 'Puff::Rule';

use Puff::PPIUtil qw( call_args is_builtin_call );
use Scalar::Util  qw( refaddr );

sub code       {'S013'}
sub summary    {'Variable interpolated or concatenated into SQL'}
sub applies_to { [ 'PPI::Token::Quote', 'PPI::Token::HereDoc' ] }
sub fix_safety {'none'}
sub cwe        {89}

sub options {
    return {
        'quoting-methods'     => [qw( quote quote_identifier )],
        'safe-functions'      => [qw( int abs hex oct length scalar )],
        'upper-case-keywords' => 0,
    };
}

sub explanation {
    return <<~'END';
        Building SQL by pasting values into a string lets those values
        change the statement. A `$name` of `x' OR '1'='1` turns this lookup
        into a query that matches every row:

            my $sql = "SELECT * FROM users WHERE name = '$name'";

        Pass values as placeholders instead, and let the driver quote them:

            my $sth = $dbh->prepare('SELECT * FROM users WHERE name = ?');
            $sth->execute($name);

        A table or column name cannot be a placeholder; quote it with
        `$dbh->quote_identifier($table)`.

        The rule looks at strings that read as SQL: they start with
        SELECT, INSERT, UPDATE, DELETE, REPLACE, ALTER, DROP, CREATE or
        TRUNCATE, and the text has the matching clause (`SELECT ... FROM`,
        `INSERT INTO`, `UPDATE ... SET`, `DELETE FROM`, `DROP TABLE` and
        so on). A heredoc whose terminator is `SQL` always counts, and so
        does a string appended with `.=` to a variable that holds SQL or
        whose name contains `sql`. In such a string, the rule reports:

        - variables interpolated into it, as in `"... WHERE id = $id"`;
        - variables and function or method calls joined to it with `.`;
        - `%s` arguments of `sprintf` when the format is SQL.

        These are not reported: calls to a quoting method (`$dbh->quote($v)`,
        `$dbh->quote_identifier($t)`, also inside `@{[ ... ]}`), the
        functions in `safe-functions`, constants written as barewords, and
        a `join` that builds placeholders or quoted values
        (`join ',', ('?') x @ids`). Numeric `sprintf` conversions such as
        `%d` are safe too.

        A comment `## SQL safe ($var, &function)` on a line of the
        statement marks those variables and functions as checked, as in
        Perl::Critic. Prefer placeholders where you can: a later edit can
        make a checked variable unsafe without anyone noticing.

        Option `quoting-methods` (default `["quote", "quote_identifier"]`):
        methods or functions whose result is safely quoted.

        Option `safe-functions` (default `["int", "abs", "hex", "oct",
        "length", "scalar"]`): functions whose result is safe to put in
        SQL. Name a package function in full (`My::DB::quote_list`).

        Option `upper-case-keywords` (default `false`): only treat strings
        as SQL when the keywords are in upper case, for code bases where
        that is the convention and lower-case matches are prose.
        END
}

sub check ( $self, $elem, $doc ) {
    return unless _is_anchor($elem);
    my @parts = _chain($elem);
    return unless $self->_is_sql( $elem, \@parts, $doc );
    my %safe = _safe_marks( $elem, $doc );
    my %seen;
    my @found = grep { !_is_marked( \%safe, $_ ) && !$seen{$_}++ }
        ( map { $self->_injections($_) } @parts ), $self->_sprintf_injections($elem);
    return unless @found;
    my $what = join q{, }, @found;
    return $self->violation(
        $elem,
        message => "Possible SQL injection: $what in SQL; use placeholders or \$dbh->quote",
        fixable => 0,
    );
}

# $h{x} and $h->{x} are covered by a mark for $h.
sub _is_marked ( $safe, $name ) {
    return 1 if $safe->{$name};
    my ($base) = $name =~ /\A([\$\@]\w+(?:::\w+)*)/ or return 0;
    return $safe->{$base} ? 1 : 0;
}

# A string is checked once, from the first string of its `.` chain.
sub _is_anchor ($elem) {
    for ( my $prev = $elem->sprevious_sibling; $prev; $prev = $prev->sprevious_sibling ) {
        return 0 if _is_string($prev);
        next     if $prev->isa('PPI::Token::Operator') && ( $prev->content eq q{.} || $prev->content eq '->' );
        return 1 if $prev->isa('PPI::Token::Operator') || $prev->isa('PPI::Token::Structure');
    }
    return 1;
}

sub _is_string ($el) {
    return $el->isa('PPI::Token::Quote') || $el->isa('PPI::Token::HereDoc');
}

# The operands joined by `.` from $elem on, each an arrayref of elements.
sub _chain ($elem) {
    my @parts;
    my $el = $elem;
    while ($el) {
        my @operand = _operand($el) or last;
        push @parts, \@operand;
        my $op = $operand[-1]->snext_sibling;
        last unless $op && $op->isa('PPI::Token::Operator') && $op->content eq q{.};
        $el = $op->snext_sibling;
    }
    return @parts;
}

# The elements of one operand starting at $el: a string, a variable with
# its subscripts and method calls, or a function call with its arguments.
sub _operand ($el) {
    return $el if _is_string($el) || $el->isa('PPI::Token::Number');
    return     if !( $el->isa('PPI::Token::Symbol') || $el->isa('PPI::Token::Word') || $el->isa('PPI::Token::Magic') );
    my @operand = ($el);
    if ( $el->isa('PPI::Token::Word') && ( my $args = $el->snext_sibling ) ) {
        push @operand, $args if $args->isa('PPI::Structure::List');
    }
    while ( my $next = $operand[-1]->snext_sibling ) {
        if ( $next->isa('PPI::Structure::Subscript') ) {
            push @operand, $next;
            next;
        }
        last unless $next->isa('PPI::Token::Operator') && $next->content eq '->';
        my $after = $next->snext_sibling or last;
        if ( $after->isa('PPI::Structure::Subscript') ) {
            push @operand, $next, $after;
            next;
        }
        last unless $after->isa('PPI::Token::Word');
        push @operand, $next, $after;
        my $args = $after->snext_sibling;
        push @operand, $args if $args && $args->isa('PPI::Structure::List');
    }
    return @operand;
}

# Text that starts like an SQL statement and has its matching clause.
my $SQL_SOURCE = q{
    \A \s* (?:
        SELECT \b .*? \b FROM \b
      | (?: INSERT | REPLACE ) \s+ (?: (?: IGNORE | OR \s+ \w+ ) \s+ )? INTO \b
      | UPDATE \s+ \S+ \s+ SET \b
      | DELETE \s+ FROM \b
      | (?: ALTER | DROP | CREATE (?: \s+ OR \s+ REPLACE )? ) \s+ (?: TEMP (?:ORARY)? \s+ )?
        (?: TABLE | INDEX | VIEW | DATABASE | SCHEMA | SEQUENCE | TRIGGER | FUNCTION | PROCEDURE | USER | ROLE ) \b
      | TRUNCATE \s+ \S
    )
};
my $SQL        = qr/$SQL_SOURCE/sx;
my $SQL_NOCASE = qr/$SQL_SOURCE/six;

sub _is_sql ( $self, $elem, $parts, $doc ) {
    return 1 if $elem->isa('PPI::Token::HereDoc') && ( $elem->terminator // q{} ) eq 'SQL';
    return 1 if $self->_appends_to_sql( $elem, $doc );
    return $self->_reads_as_sql( join q{ }, map { _text($_) } @$parts );
}

sub _reads_as_sql ( $self, $text ) {
    return 0 unless $text =~ ( $self->option('upper-case-keywords') ? $SQL : $SQL_NOCASE );

    # "Select a file" is prose; SQL keywords are all upper or all lower case.
    my ($keyword) = $text =~ /\A\s*(\w+)/;
    return $keyword eq uc $keyword || $keyword eq lc $keyword ? 1 : 0;
}

# The literal text of an operand; other operands stand in as `x`.
sub _text ($operand) {
    my $el = $operand->[0];
    return join q{}, $el->heredoc if $el->isa('PPI::Token::HereDoc');
    return $el->string            if $el->isa('PPI::Token::Quote');
    return 'x';
}

# $sql .= " WHERE id = $id"
sub _appends_to_sql ( $self, $elem, $doc ) {
    my $op = $elem->sprevious_sibling;
    return 0 unless $op && $op->isa('PPI::Token::Operator') && $op->content eq '.=';
    my $target = $op->sprevious_sibling;
    return 0 unless $target && $target->isa('PPI::Token::Symbol');
    return 1 if $target->content =~ /sql/i;
    return $self->_sql_variables($doc)->{ $target->content } ? 1 : 0;
}

# Variables assigned a string that reads as SQL somewhere in $doc.
sub _sql_variables ( $self, $doc ) {
    my $cache = $self->{_sql_variables};
    return $cache->[1] if $cache && refaddr( $cache->[0] ) == refaddr($doc);
    my %vars;
    for my $op ( @{ $doc->find( sub { $_[1]->isa('PPI::Token::Operator') && $_[1]->content eq q{=} } ) || [] } ) {
        my $string = $op->snext_sibling;
        next unless $string && _is_string($string);
        my $target = $op->sprevious_sibling or next;
        next unless $target->isa('PPI::Token::Symbol');
        my $text = join q{ }, map { _text($_) } _chain($string);
        $vars{ $target->content } = 1 if $self->_reads_as_sql($text);
    }
    $self->{_sql_variables} = [ $doc, \%vars ];
    return \%vars;
}

# The unsafe names in one operand.
sub _injections ( $self, $operand ) {
    my $el = $operand->[0];
    return $self->_interpolated($el) if _is_string($el);
    return if $el->isa('PPI::Token::Number');
    return if $self->_is_quoted($operand);
    if ( $el->isa('PPI::Token::Symbol') || $el->isa('PPI::Token::Magic') ) {
        return join q{}, map { $_->content } @$operand;
    }
    my $name = _function_name($operand) // return;    # a bareword constant
    return if $self->_is_safe_function( $name, $operand );
    return $name . q{()};
}

sub _is_quoted ( $self, $operand ) {
    my %quoting = map { $_ => 1 } @{ $self->option('quoting-methods') };
    return grep { $_->isa('PPI::Token::Word') && $quoting{ $_->content } } @$operand;
}

# foo(...) => foo, Foo->bar(...) => Foo::bar; undef for a bareword constant.
sub _function_name ($operand) {
    my ( $word, $next ) = @$operand;
    return $word->content if $next && $next->isa('PPI::Structure::List');
    return unless $next && $next->isa('PPI::Token::Operator') && $next->content eq '->';
    return $word->content . q{::} . $operand->[2]->content;
}

sub _is_safe_function ( $self, $name, $operand ) {
    my %safe = map { $_ => 1 } @{ $self->option('safe-functions') };
    return 1 if $safe{$name};
    return 0 unless $name eq 'join' && is_builtin_call( $operand->[0] );
    # join ',', ('?') x @ids  /  join ',', map { $dbh->quote($_) } @ids
    my $args = join q{}, map { $_->content } @$operand[ 1 .. $#$operand ];
    return $args =~ /(['"])\?\1/ || $self->_mentions_quoting($args) ? 1 : 0;
}

sub _mentions_quoting ( $self, $code ) {
    my $methods = join q{|}, map {quotemeta} @{ $self->option('quoting-methods') };
    return $methods ne q{} && $code =~ /\b(?:$methods)\b/;
}

my $NAME          = qr/\^\w|\w+(?:::\w+)*|\{\s*\^?\w+\s*\}/;
my $INTERPOLATION = qr/
    (?<!\\) (?:\\\\)*
    (
        [\$\@] \{ \s* \[ .*? \] \s* \}         # @{[ expr ]}
      | \$\$ (?!\w|\{) (*SKIP)(*FAIL)         # $$, the pid
      | [\$\@] \$* $NAME (?: (?:->)? (?: \[ [^\]]* \] | \{ [^\}]* \} ) )*
    )
/x;

# Variables and expressions interpolated into a string.
sub _interpolated ( $self, $el ) {
    my $text;
    if ( $el->isa('PPI::Token::HereDoc') ) {
        return if $el->content =~ /\A<<~?\s*'/;
        $text = join q{}, $el->heredoc;
    }
    elsif ( $el->isa('PPI::Token::Quote::Double') || $el->isa('PPI::Token::Quote::Interpolate') ) {
        $text = $el->string;
    }
    else {
        return;
    }
    my @found;
    while ( $text =~ /$INTERPOLATION/g ) {
        my $var = $1;
        if ( $var =~ /\A[\$\@]\{\s*\[/ ) {
            push @found, '@{[ ... ]}' unless $self->_mentions_quoting($var);
            next;
        }
        push @found, $var =~ s/\A([\$\@])\{\s*(\w+)\s*\}/$1$2/r;
    }
    return @found;
}

# sprintf('SELECT * FROM %s WHERE id = %d', $table, $id): the %s arguments.
sub _sprintf_injections ( $self, $elem ) {
    my $word = _sprintf_word($elem) // return;
    my $args = call_args($word);
    return unless @$args && @{ $args->[0] } == 1 && refaddr( $args->[0][0] ) == refaddr($elem);
    my @found;
    my $i      = 0;
    my $format = $elem->string;
    while ( $format =~/%(?:%|[-+ 0#]*(?:\*|\d+)?(?:\.(?:\*|\d+))?(?:[hlqLV]|ll)?([a-zA-Z]))/g ) {
        my $conv = $1 // next;
        $i++;
        next unless $conv eq 's';
        my $arg = $args->[$i] or next;
        my @operand = _operand( $arg->[0] );
        next unless @operand == @$arg;
        push @found, $self->_injections( \@operand );
    }
    return @found;
}

sub _sprintf_word ($elem) {
    my $parent = $elem->parent or return;
    my $word;
    if ( $parent->isa('PPI::Statement::Expression') && $parent->parent && $parent->parent->isa('PPI::Structure::List') ) {
        $word = $parent->parent->sprevious_sibling;
    }
    else {
        $word = $elem->sprevious_sibling;
    }
    return unless $word && $word->isa('PPI::Token::Word') && $word->content =~ /\A(?:CORE::)?sprintf\z/;
    return is_builtin_call($word) ? $word : undef;
}

# Names marked safe by `## SQL safe ($var, &function)` on a line of the
# statement holding $elem.
sub _safe_marks ( $elem, $doc ) {
    my $stmt  = $elem->statement // $elem;
    my $first = $stmt->first_token->line_number;
    my $last  = $stmt->last_token->line_number;
    my %safe;
    for my $comment ( @{ $doc->find('PPI::Token::Comment') || [] } ) {
        my $line = $comment->line_number;
        next if $line < $first || $line > $last;
        my ($list) = $comment->content =~ /\A\#\#\s*SQL\s+safe\s*\(\s*(.*?)\s*\)/i or next;
        for my $name ( split /[\s,]+/, $list ) {
            $name =~ s/\A&//;
            $safe{$name} = 1;
            $safe{"$name()"} = 1;
        }
    }
    return %safe;
}

1;

# ABSTRACT: S013 - variable interpolated or concatenated into SQL

__END__

=pod

=head1 DESCRIPTION

Reports variables and calls that are interpolated or concatenated into a
string that reads as SQL, which risks SQL injection. Placeholders or a
quoting method such as C<< $dbh->quote >> make the value safe. There is no
fix.

Based on L<Perl::Critic::Policy::ValuesAndExpressions::PreventSQLInjection>,
with its C<## SQL safe (...)> comments, extended to C<sprintf> formats and
C<.=> fragments.

Selected by default, as part of C<S>.

=cut
