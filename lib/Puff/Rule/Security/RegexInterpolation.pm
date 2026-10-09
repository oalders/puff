package Puff::Rule::Security::RegexInterpolation;

use v5.36;
use parent 'Puff::Rule';

use Puff::Violation ();
use Scalar::Util    qw( refaddr weaken );

sub code       {'S019'}
sub summary    {'Variable interpolated into a regex without \Q'}
sub applies_to { [ 'PPI::Token::Regexp::Match', 'PPI::Token::Regexp::Substitute', 'PPI::Token::QuoteLike::Regexp' ] }
sub fix_safety {'unsafe'}
sub cwe        { ( 625, 1333 ) }
sub explicit_select {1}

sub explanation {
    return <<~'END';
        A variable interpolated into a regex becomes part of the pattern.
        If it holds input, the metacharacters in it change what the pattern
        matches: `.` matches anything, `|` adds an alternative, and an
        unbalanced `(` makes the regex die (CWE-625, permissive regular
        expression). A crafted value can also make the regex engine
        backtrack catastrophically when the resulting pattern is vulnerable
        to it (CWE-1333, inefficient regular expression complexity).
        `\Q$var\E` (or `quotemeta`) matches the value as literal text.

        The rule reports a scalar variable (`$x`, `${x}`, `$$x`,
        `$x->{k}`, `$h{k}`, `$x->[0]` and the like) interpolated into the
        pattern of `m//`, `//`, `s///`, `qr//` or a `split` regex, outside
        `\Q...\E`. `${x}` ends at its closing brace: in `${x}{k}` and
        `${x}[0]` only `${x}` is the variable.

        It does not report the replacement side of `s///`, a pattern with
        `'` delimiters (`m'...'`), which does not interpolate, or a
        variable inside `\Q...\E` (or after a `\Q` with no `\E`). It also
        skips some variables on heuristics that guess the value is a
        pattern or not input. The guesses can be wrong, so these skips can
        hide real injection; S019 is not a complete detector:

        - a variable whose own name looks like a regex: `re`, `rx`,
          `regex`, `regexp`, `pattern` or `pat` as a whole word of the name
          (`$re`, `$re_word`, `$word_rx`, `$pats`), or `regex` or
          `pattern` anywhere in it. Hash keys are not checked, so
          `$args->{pattern}` is reported;
        - a plain scalar whose only assignment visible before the regex
          is `$x = qr/.../` or `$x = quotemeta ...`, with nothing else on
          the right-hand side. "Visible" means a statement earlier in the
          same block or an enclosing block (or the file). A same-named
          variable in another sub does not count, and
          `$x = $opt{x} // qr/.../` is reported;
        - a plain scalar with an all-caps name (`$WS`, `$CRLF`,
          `$Foo::CRLF`), taken to be a constant. `$Input` is reported;
        - capture and punctuation variables (`$1`, `$&`, `$^N`,
          `${^MATCH}`), as the issue that added the rule asked: a capture
          is usually a substring of the string being matched;
        - `$` used as an anchor (`/foo$/`, `/(a$)/`) and code blocks
          (`(?{ ... })`);
        - arrays (`@x`, `@{[ ... ]}`).

        A pattern held in a variable and matched directly (`$s =~ $x`) or
        a string passed to `split` is not reported.

        The unsafe fix wraps the variable, with its subscripts, in
        `\Q...\E`. It changes what the regex matches when the variable is
        meant to hold a pattern, which is why the fix is unsafe and the
        rule is opt-in. The variable is reported with no fix, and the
        message says why, when:

        - a quantifier follows it (`$x+`, `$x*`, `$x?`, `$x{2,3}`): after
          `\Q$x\E` it would apply to the last character only;
        - it is inside a character class (`[$x]`);
        - it is inside a comment of a `/x` pattern.

        There is also no fix when the extent of the variable is uncertain:
        `${ expr }`, a `[` right after the name (Perl guesses whether it
        starts a subscript or a character class), postfix dereference, an
        old-style `'` package separator or a trailing `::` after the name,
        an unclosed subscript, or a delimiter other than common
        punctuation.

        This rule is selected only by its code or `ALL`, not by `S`.
        END
}

# Delimiters whose patterns the fix rewrites. Others (a letter, `$`, `@`,
# `-` and the like) make the extent of a variable uncertain.
my %FIX_DELIM = map { $_ => 1 } split //, '/{([<!|#,~%^;:=+?"';

# A variable name that suggests it holds a pattern. Only the variable's own
# name is checked, never a hash key: $args->{pattern} is often input.
my $REGEX_NAME = qr/(?:\A|_)(?:re|rx|regexp?|pattern|pat)(?:_|\z|s\z)|regex|pattern/i;

# An all-caps name such as $WS or $CRLF: by convention a constant, which is
# often, though not always, a pattern rather than input.
my $CONSTANT_NAME = qr/\A[A-Z][A-Z0-9_]*\z/;

# A quantifier such as {2}, {2,} or {2,5} after a variable, rather than a
# hash subscript.
my $QUANTIFIER = qr/\G\{\s*(?:\d+\s*(?:,\s*\d*\s*)?|,\s*\d+\s*)\}/;

my %NO_FIX = (
    quantifier => 'a quantifier follows it, and after \Q...\E it would apply to the last character only',
    class      => 'it is inside a character class',
    comment    => 'it is inside a /x comment',
);

sub check ( $self, $elem, $doc ) {
    my @violations;
    for my $found ( _findings( $elem, $doc ) ) {
        my $message
            = "$found->{text} interpolated into a regex without \\Q...\\E; metacharacters in it change the match";
        $message .= "; no fix: $NO_FIX{ $found->{no_fix} }" if $found->{no_fix};
        push @violations, Puff::Violation->new(
            rule    => $self,
            code    => $self->code,
            element => $elem,
            line    => $found->{line},
            column  => $found->{column},
            message => $message,
            fixable => $found->{fixable},
        );
    }
    return @violations;
}

sub fix ( $self, $violation, $fix ) {
    my $elem = $violation->element;
    my ($found)
        = grep { $_->{line} == $violation->line && $_->{column} == $violation->column } _findings( $elem, $elem->top );
    return 0 unless $found && $found->{fixable};
    my $start = $fix->source->start_of($elem) + $found->{offset};
    $fix->replace_range( $start, $start, '\Q' );
    $fix->replace_range( $start + length $found->{text}, $start + length $found->{text}, '\E' );
    return 1;
}

# The variables to report in the pattern of $elem: a list of { text,
# offset (in the token's content), line, column, fixable, no_fix }.
sub _findings ( $elem, $doc ) {
    my $section = $elem->{sections} && $elem->{sections}[0] or return;
    my $open    = substr $section->{type}, 0, 1;
    return if $open eq q{'};

    my $pattern = substr $elem->content, $section->{position}, $section->{size};
    my %mod     = $elem->get_modifiers;
    my $loc     = $elem->location or return;
    my @found;
    for my $var ( _variables( $pattern, $mod{x} ) ) {
        next if $var->{short} =~ $REGEX_NAME;

        # $1 and the like are not returned by _variables: the issue asked for
        # them to be skipped, and a capture is usually a substring of the
        # string being matched.
        if ( defined $var->{name} && !$var->{subscripted} && !$var->{deref} ) {
            next if $var->{short} =~ $CONSTANT_NAME || _holds_pattern( $elem, $doc, $var->{name} );
        }
        my $offset = $section->{position} + $var->{start};
        my $before = substr $elem->content, 0, $offset;
        my $nl     = () = $before =~ /\n/g;
        push @found, {
            text    => $var->{text},
            offset  => $offset,
            line    => $loc->[0] + $nl,
            column  => $nl ? length( $before =~ s/.*\n//sr ) + 1                   : $loc->[1] + $offset,
            fixable => $var->{certain} && !$var->{no_fix} && $FIX_DELIM{$open} ? 1 : 0,
            no_fix  => $var->{no_fix},
        };
    }
    return @found;
}

# Scans a pattern as Perl interpolates it and returns the scalar variables
# outside \Q...\E: { start, text, name, short, subscripted, deref, certain,
# no_fix }. $x is true under the /x modifier.
sub _variables ( $pattern, $x ) {
    my ( @found, @case, $class, $comment );
    pos($pattern) = 0;
    while ( pos($pattern) < length $pattern ) {
        if ( $pattern =~ /\G\\([QLUF])/gc ) { push @case, $1; next }
        if ( $pattern =~ /\G\\E/gc )        { pop @case;      next }
        next if $pattern =~ /\G\\c./gcs || $pattern =~ /\G\\./gcs;

        # Character classes ([]a] and [^]a] start with a literal ]) and,
        # under /x, comments from an unescaped # to the end of the line.
        if ($comment) {
            $comment = 0 if $pattern =~ /\G\n/gc;
        }
        elsif ($class) {
            next if $pattern =~ /\G\[:\^?\w+:\]/gc;    # [:alpha:]
            if ( $pattern =~ /\G\]/gc ) { $class = 0; next }
        }
        else {
            if ( $pattern       =~ /\G\[\^?\]?/gc ) { $class   = 1; next }
            if ( $x && $pattern =~ /\G#/gc )        { $comment = 1; next }
        }

        # Code blocks hold Perl code, not interpolation.
        if ( $pattern =~ /\G\((?:\?\??|\*)(?=\{)/gc ) { _skip_brackets( \$pattern ); next }

        # Arrays and @{[ ... ]} are not reported, nor what is inside them.
        if ( $pattern =~ /\G\@(?=\{)/gc ) { _skip_brackets( \$pattern ); next }
        next if $pattern =~ /\G\@\$*(?:::)?\w+(?:::\w+)*/gc;

        my $start = pos $pattern;
        if ( $pattern =~ /\G\$(?=[()| \r\n\t]|\z)/gc ) {next}    # an anchor
        if ( $pattern =~ /\G\$/gc ) {
            my $var = _variable( \$pattern, $start );
            next unless $var && !grep { $_ eq 'Q' } @case;
            my $space = $x ? '\s*' : q{};
            $var->{no_fix}
                = $comment                                                         ? 'comment'
                : $class                                                           ? 'class'
                : $pattern =~ /\G$space[+*?]/ || $pattern =~ /\G$space$QUANTIFIER/ ? 'quantifier'
                :                                                                    undef;
            push @found, $var;
            next;
        }
        pos($pattern)++;
    }
    return @found;
}

# The variable whose `$` is at $start (pos is just after it), or undef for a
# punctuation variable. Leaves pos after the variable.
sub _variable ( $ref, $start ) {
    my %var = ( start => $start, certain => 1 );
    if ( $$ref =~ /\G\#/gc ) {    # $#x, $#{x}, $#$x: not a scalar
        _skip_brackets($ref) if $$ref =~ /\G(?=\{)/;
        $$ref =~ /\G\$*\w+/gc;
        return;
    }

    # Lookaheads below match without /g: a zero-length /gc match right
    # after another at the same position always fails.
    $var{deref} = $$ref =~ /\G(\$+)/gc ? length $1 : 0;

    my $braced;
    if ( $$ref =~ /\G\{\s*\^\w+\s*\}/gc ) {return}                      # ${^MATCH}
    if ( $$ref =~ /\G\{\s*((?:::)?[A-Za-z_]\w*(?:::\w+)*)\s*\}/gc ) {
        $var{name} = $1;
        $braced = 1;
    }
    elsif ( $$ref =~ /\G(?=\{)/ ) {                                     # ${ expr }
        _skip_brackets($ref);
        $var{certain} = 0;
    }
    elsif ( $$ref =~ /\G((?:::)?[A-Za-z_]\w*(?:::\w+)*)/gc ) {
        $var{name}    = $1;
        $var{certain} = 0 if $$ref =~ /\G(?=::|'[A-Za-z_])/;
    }
    else {
        $$ref =~ /\G(?:\d+|\^\w|.)/gcs;    # $1, $^N, $&, $. and other punctuation variables
        return;
    }
    $var{short} = defined $var{name} ? $var{name} =~ s/.*:://r : q{};

    # ${x} ends the variable: "${x}{a}", "${x}[0]" and "${x}->[0]" are $x
    # followed by pattern text.
    while ( !$braced ) {
        my $arrow = $$ref =~ /\G->(?=[\[{])/gc;

        # After an arrow or a first subscript, [ and { always continue the
        # variable. Right after the name, Perl guesses whether [ starts a
        # subscript or a character class (taken here as a subscript, with no
        # fix), and reads {2} as a quantifier.
        my $explicit = $arrow || $var{subscripted};
        if ( $$ref =~ /\G(?=\[)/ ) {
            $var{certain} = 0 unless $explicit;
        }
        elsif ( $$ref =~ /\G(?=\{)/ ) {
            last if !$explicit && $$ref =~ $QUANTIFIER;
        }
        else {
            $var{certain} = 0 if $$ref =~ /\G->[\$\@%&*]/;    # postfix deref
            last;
        }
        _skip_brackets($ref) or $var{certain} = 0;
        $var{subscripted} = 1;
    }
    $var{text} = substr $$ref, $start, pos($$ref) - $start;
    return \%var;
}

# Moves pos past the bracketed group that starts at pos, honouring nesting
# and backslashes. Returns false, at the end of the string, when the group is
# not closed.
sub _skip_brackets ($ref) {
    my ( $open, $close ) = $$ref =~ /\G\{/ ? ( '{', '}' ) : ( '[', ']' );
    my $depth = 0;
    while ( $$ref =~ /\G(?:\\.|([^\\]))/gcs ) {
        next unless defined $1;
        $depth++ if $1 eq $open;
        $depth-- if $1 eq $close;
        return 1 if $depth == 0;
    }
    return 0;
}

my ( $cached_doc, $cached );

# Whether $name is assigned a pattern in a statement visible from $elem: a
# statement before it in the same block, or in a block or document enclosing
# it. This approximates lexical scope; it does not follow later assignments.
sub _holds_pattern ( $elem, $doc, $name ) {
    my $assigned = _pattern_assignments($doc)->{$name} or return 0;
    my %enclosing;
    for ( my $p = $elem->parent ; $p ; $p = $p->parent ) { $enclosing{ refaddr $p } = 1 }
    my $loc = $elem->location;
    for my $stmt (@$assigned) {
        next if $enclosing{ refaddr $stmt } || !$enclosing{ refaddr $stmt->parent };
        my $at = $stmt->location;
        return 1 if $at->[0] < $loc->[0] || ( $at->[0] == $loc->[0] && $at->[1] < $loc->[1] );
    }
    return 0;
}

# The statements of the document that assign a plain scalar a pattern, by
# variable name: `[my|our|state|local] $x = qr/.../;`, `$x = quotemeta(...);`
# or `$x = quotemeta EXPR;`, with nothing else on the right-hand side.
sub _pattern_assignments ($doc) {
    return $cached if $cached_doc && refaddr($cached_doc) == refaddr($doc);
    $cached_doc = $doc;
    weaken($cached_doc);
    my %by_name;
    for my $symbol ( @{ $doc->find('PPI::Token::Symbol') || [] } ) {
        next unless $symbol->content =~ /\A\$((?:::)?\w+(?:::\w+)*)\z/;
        my $name = $1;
        my $stmt = $symbol->parent;
        next unless $stmt->isa('PPI::Statement') && $stmt->parent;
        my $prev = $symbol->sprevious_sibling;
        next if $prev && !( $prev->isa('PPI::Token::Word') && $prev->content =~ /\A(?:my|our|state|local)\z/ );
        next if $prev && $prev->sprevious_sibling;
        my $op = $symbol->snext_sibling;
        next unless $op && $op->isa('PPI::Token::Operator') && $op->content eq '=';
        my $first = $op->snext_sibling or next;
        my @rhs   = ($first);
        while ( my $next = $rhs[-1]->snext_sibling ) { push @rhs, $next }
        pop @rhs if $rhs[-1]->isa('PPI::Token::Structure') && $rhs[-1]->content eq ';';
        push @{ $by_name{$name} }, $stmt if _is_pattern(@rhs);
    }
    return $cached = \%by_name;
}

# Whether the elements of a right-hand side are one qr// or one quotemeta call.
sub _is_pattern (@rhs) {
    return 1 if @rhs == 1 && $rhs[0]->isa('PPI::Token::QuoteLike::Regexp');
    my $word = shift @rhs;
    return 0 unless $word && $word->isa('PPI::Token::Word') && $word->content eq 'quotemeta' && @rhs;
    return 1 if @rhs == 1 && $rhs[0]->isa('PPI::Structure::List');

    # quotemeta EXPR: a variable, its subscripts and arrows, and nothing else.
    return 0 unless $rhs[0]->isa('PPI::Token::Symbol');
    for my $el ( @rhs[ 1 .. $#rhs ] ) {
        next if $el->isa('PPI::Structure::Subscript') || ( $el->isa('PPI::Token::Operator') && $el->content eq '->' );
        return 0;
    }
    return 1;
}

1;

# ABSTRACT: S019 - variable interpolated into a regex without \Q

__END__

=pod

=head1 DESCRIPTION

Reports a scalar variable interpolated into the pattern of C<m//>, C<//>,
C<s///>, C<qr//> or a C<split> regex outside C<\Q...\E>. Metacharacters in
the variable's value change what the pattern matches (CWE-625), and a
crafted value can make the regex engine backtrack catastrophically when the
resulting pattern is vulnerable to it (CWE-1333). The violation is reported
at the variable, so a regex with two such variables has two.

The pattern is scanned the way Perl interpolates it: backslash escapes,
C<\Q>, C<\L>, C<\U> and C<\F> (each ended by its own C<\E>), C<$> as an
anchor before C<)>, C<|>, whitespace or the end, code blocks such as
C<(?{ ... })>, character classes, C<#> comments under C</x>, and a C<{...}>
after a variable that is a quantifier rather than a subscript. C<${x}> ends
at its closing brace, so in C<${x}{k}> only C<${x}> is the variable. The
replacement of C<s///> and patterns with C<'> delimiters are not looked at.

Some variables are skipped on heuristics that guess the value is a pattern
or not input. The guesses can be wrong, so the skips can hide real
injection: S019 is not a complete detector. Skipped:

=over

=item *

a variable whose own name has C<re>, C<rx>, C<regex>, C<regexp>, C<pattern>
or C<pat> as a whole C<_>-separated word, or plural (C<$re>, C<$word_rx>,
C<$pats>), or C<regex> or C<pattern> anywhere in it. Hash keys are not
checked: C<< $args->{pattern} >> is reported;

=item *

a plain scalar with an all-caps name (C</\A[A-Z][A-Z0-9_]*\z/>, checked on
the last C<::> component), such as C<$WS> or C<$Foo::CRLF>, taken to be a
constant. C<$Input> and C<$Pkg::Const> are reported;

=item *

a plain scalar assigned C<qr/.../> or C<quotemeta(...)> / C<quotemeta EXPR>
with C<=>, with nothing else on the right-hand side, in a statement before
the regex in the same block or an enclosing block (or the file). This
approximates lexical scope: a same-named variable in another sub does not
count, but a later reassignment is not noticed. C<$x = $opt{x} // qr/,/>,
C<$x ||= qr/,/> and C<join '|', map {quotemeta} @w> are reported;

=item *

capture and punctuation variables (C<$1>, C<$&>, C<$^N>, C<${^MATCH}>), as
the issue that added the rule asked, since a capture is usually a substring
of the string being matched; C<$#x>; and arrays, including C<@{[ ... ]}>.

=back

The unsafe fix wraps the variable and its subscripts in C<\Q...\E>. When the
variable was meant to hold a pattern the fix changes what the regex matches,
which is why the fix is unsafe and why the rule is selected only by its
exact code (C<S019>) or C<ALL>. The variable is reported with no fix, with
the reason in the message, when a quantifier follows it (C<$x+>,
C<$x{2,3}>; after C<\Q$x\E> it would apply to the last character only),
when it is inside a character class (C<[$x]>), or when it is inside a
comment of a C</x> pattern. There is also no fix when the extent of the
variable in the pattern is uncertain: C<${ expr }>, a C<[> right after the
name (Perl guesses whether it starts a subscript or a character class),
postfix dereference, a C<'> or trailing C<::> after the name, an unclosed
subscript, or a delimiter other than common punctuation.

Matching against a variable directly (C<$s =~ $x>) and a string pattern
given to C<split> are not reported.

=cut
