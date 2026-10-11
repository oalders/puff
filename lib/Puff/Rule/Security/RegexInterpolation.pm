package Puff::Rule::Security::RegexInterpolation;

use v5.36;
use parent 'Puff::Rule';

use Puff::Violation     ();
use Puff::LexicalScopes qw( declarations );
use Scalar::Util        qw( refaddr weaken );

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
        variable inside `\Q...\E` (or after a `\Q` with no `\E`). As in
        Perl, a `\L`, `\U` or `\F` ends an active `\L`, `\U` or `\F` and
        any `\Q` after it, so in `\Qa\Ub\Lc\E\E$x` the second `\E` ends
        the first `\Q` and `$x` is reported. It also
        skips some variables on heuristics that guess the value is a
        pattern or not input. The guesses can be wrong, so these skips can
        hide real injection; S019 is not a complete detector:

        - a variable whose own name looks like a regex: `re`, `rx`,
          `regex`, `regexp`, `pattern` or `pat` as a whole word of the name
          (`$re`, `$re_word`, `$word_rx`, `$pats`), or `regex` or
          `pattern` anywhere in it. Hash keys are not checked, so
          `$args->{pattern}` is reported;
        - a plain scalar whose nearest declaration visible from the regex
          is a whole statement `my $x = qr/.../;` or `my $x =
          quotemeta ...;` (also `our` or `state`), with nothing else on the
          right-hand side. The search goes from the innermost enclosing
          block outwards, taking the latest declaration before the regex,
          and counts `my`, `our` and `state` (list forms included), `for
          my $v` loop variables and sub signature parameters. So an inner
          `my $x = shift`, `for my $x (...)`, `sub f ($x)` or `my ($x) =
          @_` hides an outer `my $x = qr/.../`. For a global with no
          declaration, a qualifying assignment `$x = qr/.../;` (or
          `local $x = qr/.../;`) in an
          earlier statement of the same or an enclosing block (or the
          file) is needed instead. Either way the file must write the name
          nowhere else: any other assignment (`=`, `.=`, `||=`, `//=` and
          the like, in any scope), `local $x` other than a qualifying
          `local $x = qr/.../;`, a `foreach` loop over it or
          over a list holding it, a reference `\$x`, `$x++` or `--$x`,
          `chomp`, `chop`, `open`, `opendir`, `read`, `recv` or `sysread`
          changing it (as a direct argument of the builtin, not of a method
          or a nested call), or `$x =~ s///` or `tr///` (also `($x) =~
          s///`) means it is reported. A write to `$Pkg::x`,
          `$::x`, `${Pkg::x}` or `$Pkg'x` counts as a write to `$x`, and a
          write to `$x` counts for `$Pkg::x`. Writes through `@_`, the `$_`
          of `map` or `grep`, a glob or a symbolic name (`${'main::x'}`,
          `$::{x}`) are not seen. An assignment
          inside a condition (`if (my $x = qr/a/)`) is not seen, which errs
          towards reporting, and `$x = $opt{x} // qr/.../` is reported;
        - a plain scalar with an all-caps name (`$WS`, `$CRLF`,
          `$Foo::CRLF`), taken to be a constant. `$Input` is reported;
        - capture and punctuation variables (`$1`, `$&`, `$^N`,
          `${^MATCH}`, `$+{name}`), as the issue that added the rule asked: a capture
          is usually a substring of the string being matched;
        - `$` used as an anchor (`/foo$/`, `/(a$)/`) and code blocks
          (`(?{ ... })`, `(??{ ... })`);
        - arrays (`@x`, `@{ ... }`), and a scalar in the code of
          `@{[ ... ]}` that is inside the argument of `quotemeta` or a
          `\Q...\E` there. In `@{[ $y . quotemeta $x ]}`, `$y` is
          reported. The code is scanned as text, not parsed: a bracket,
          `quotemeta` or `\Q` inside a string literal in it is taken as
          code, so `@{[ '\Q' . $x ]}` hides `$x`.

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
        - it is inside a comment of a `/x` pattern;
        - it is inside the Perl code of `@{[ ... ]}`.

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
    code       => 'it is inside @{[ ... ]}, which is Perl code',
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

# The findings of the last element fixed: fix is called once per violation,
# and a regex can have many. $fixing is weakened, so it goes undef when the
# element is freed and a new element at the same address is not mistaken
# for it.
my ( $fixing, %fixing );

sub fix ( $self, $violation, $fix ) {
    my $elem = $violation->element;
    unless ( $fixing && refaddr($fixing) == refaddr($elem) ) {
        %fixing = map { ( "$_->{line}:$_->{column}" => $_ ) } _findings( $elem, $elem->top );
        $fixing = $elem;
        weaken($fixing);
    }
    my $found = $fixing{ $violation->line . q{:} . $violation->column };
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

    my $content = $elem->content;
    my $pattern = substr $content, $section->{position}, $section->{size};
    my %mod     = $elem->get_modifiers;
    my $loc     = $elem->location or return;

    # The line and column of offset $at in the token, moved forward from one
    # variable to the next so that the token is scanned once.
    my ( $line, $column, $at ) = ( @$loc[ 0, 1 ], 0 );
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
        my $skip   = substr $content, $at, $offset - $at;
        if ( my $nl = $skip =~ tr/\n// ) {
            $line += $nl;
            $column = length($skip) - rindex $skip, "\n";
        }
        else {
            $column += length $skip;
        }
        $at = $offset;
        push @found, {
            text    => $var->{text},
            offset  => $offset,
            line    => $line,
            column  => $column,
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

    # @case holds the escapes waiting for their \E. At most one of them is
    # a \L, \U or \F (see below), at index $case; $quoted counts the \Q.
    my ( $case, $quoted ) = ( undef, 0 );
    pos($pattern) = 0;
    while ( pos($pattern) < length $pattern ) {

        # As in Perl, a \L, \U or \F ends an active \L, \U or \F and every
        # escape started after it: in \Q\Ua\Lb\E\E only \Q\L remain to end.
        if ( $pattern =~ /\G\\([QLUF])/gc ) {
            my $esc = $1;
            if ( $esc eq 'Q' ) {
                $quoted++;
            }
            else {
                if ( defined $case ) {
                    $quoted -= $#case - $case;
                    splice @case, $case;
                }
                $case = @case;
            }
            push @case, $esc;
            next;
        }
        if ( $pattern =~ /\G\\E/gc ) {
            if    ( defined $case && $case == $#case ) { undef $case }
            elsif (@case)                              { $quoted-- }
            pop @case;
            next;
        }

        # A /x comment ends at a newline, even one after a backslash, which
        # the escape skip below would otherwise swallow.
        if ( $comment && $pattern =~ /\G\\?\n/gc ) { $comment = 0; next }
        next if $pattern =~ /\G\\c./gcs || $pattern =~ /\G\\./gcs;

        # Character classes ([]a] and [^]a] start with a literal ]) and,
        # under /x, comments from an unescaped # to the end of the line.
        if ($class) {
            next if $pattern =~ /\G\[:\^?\w+:\]/gc;    # [:alpha:]
            if ( $pattern =~ /\G\]/gc ) { $class = 0; next }
        }
        elsif ( !$comment ) {
            if ( $pattern       =~ /\G\[\^?\]?/gc ) { $class   = 1; next }
            if ( $x && $pattern =~ /\G#/gc )        { $comment = 1; next }
        }

        # Code blocks hold Perl code, not interpolation.
        if ( $pattern =~ /\G\((?:\?\??|\*)(?=\{)/gc ) { _skip_brackets( \$pattern ); next }

        # @{[ ... ]} interpolates the result of Perl code. Its scalars are
        # reported, with no fix, unless they are inside the argument of
        # quotemeta or a \Q...\E of the code.
        if ( $pattern =~ /\G\@(?=\{\[)/gc ) {
            my $from = pos $pattern;
            _skip_brackets( \$pattern );
            my $end = pos $pattern;
            next if $quoted;
            my $code  = substr $pattern, $from, $end - $from;
            my @spans = _quoted_spans($code);
            while ( $code =~ /\G(?:\\.|[^\\\$])*+\$/gcs ) {
                my $start = pos($code) - 1;
                pos($pattern) = $from + $start + 1;
                my $var = _variable( \$pattern, $from + $start );
                pos($code) = pos($pattern) - $from;

                # Skip a variable in a quoted part.
                shift @spans while @spans && $spans[0][1] <= $start;
                next if @spans && $spans[0][0] <= $start;

                push @found, { %$var, no_fix => 'code' } if $var && pos($pattern) <= $end;
            }
            pos($pattern) = $end;
            next;
        }

        # Arrays are not reported, nor what is inside @{ ... }.
        if ( $pattern =~ /\G\@(?=\{)/gc ) { _skip_brackets( \$pattern ); next }
        next if $pattern =~ /\G\@\$*(?:::)?\w+(?:::\w+)*/gc;

        my $start = pos $pattern;
        if ( $pattern =~ /\G\$(?=[()| \r\n\t]|\z)/gc ) {next}    # an anchor
        if ( $pattern =~ /\G\$/gc ) {
            my $var = _variable( \$pattern, $start );
            next unless $var && !$quoted;
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

# The parts of $code, the Perl code of @{[ ... ]}, that are quoted, in
# order, as [ start, end ] offsets: the argument of `quotemeta(...)`, the
# variable after `quotemeta ` (only it, which errs towards reporting), and
# `\Q` up to the next `\E` or the end.
sub _quoted_spans ($code) {
    my @spans;
    while ( $code =~ /\bquotemeta\b\s*|(\\Q)/g ) {
        my $start = pos $code;
        if    ($1)                    { $code =~ /\G.*?(?:\\E|\z)/gcs }
        elsif ( $code =~ /\G(?=\()/ ) { _skip_brackets( \$code ) }
        elsif ( $code =~ /\G\$/gc )   { _variable( \$code, $start ) }
        push @spans, [ $start, pos $code ];
    }
    return @spans;
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
    my ( $open, $close )
        = $$ref =~ /\G\{/ ? ( '{', '}' )
        : $$ref =~ /\G\(/ ? ( '(', ')' )
        :                   ( '[', ']' );
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

# Whether $name, a plain scalar used in the regex $elem, is taken to hold a
# pattern. The document must write $name nowhere but in qualifying
# assignments (see _pattern_assignment). Then the nearest declaration of
# $name visible from $elem must be a qualifying `my $x = qr/.../;`. With no
# visible declaration (a global), a qualifying assignment must be visible
# instead: a statement before $elem in the same block, or in a block or
# document enclosing it.
sub _holds_pattern ( $elem, $doc, $name ) {
    my $data = _analysis($doc);
    return 0 if $data->{writes}{$name} || ( $name =~ /::(\w+)\z/ && $data->{writes}{$1} );
    my $loc = $elem->location;
    my @parents;
    for ( my $p = $elem->parent ; $p ; $p = $p->parent ) { push @parents, $p }
    my %enclosing = map { refaddr($_) => 1 } @parents;

    if ( my $scopes = $data->{declarations}{"\$$name"} ) {
        for my $p (@parents) {
            my $decls = $scopes->{ refaddr $p } or next;

            # The latest declaration before $elem, skipping one whose
            # statement holds $elem: in `my $x = qr/$x/` the regex sees an
            # earlier $x. Only the statement holding $elem is skipped over.
            for ( my $i = _count_before( $decls, $loc ) - 1 ; $i >= 0 ; $i-- ) {
                my $decl = $decls->[$i];
                next if $decl->{statement} && $enclosing{ refaddr $decl->{statement} };
                return $data->{qualifying}{ refaddr $decl->{elem} } ? 1 : 0;
            }
        }
    }

    # A qualifying assignment in a scope enclosing $elem, before it. The
    # earliest one in each scope is enough: the statements of one scope are
    # siblings (they are keyed by their parent), so if the earliest holds
    # $elem, the others come after $elem.
    my $assigned = $data->{assigned}{$name} or return 0;
    for my $p (@parents) {
        my $stmts = $assigned->{ refaddr $p } or next;
        my $first = $stmts->[0];
        return 1 if !$enclosing{ refaddr $first->{elem} } && _before( $first->{at}, $loc );
    }
    return 0;
}

# The number of entries in $list, a list of { at } in document order, whose
# location is before $loc.
sub _count_before ( $list, $loc ) {
    my ( $lo, $hi ) = ( 0, scalar @$list );
    while ( $lo < $hi ) {
        my $mid = int( ( $lo + $hi ) / 2 );
        if   ( _before( $list->[$mid]{at}, $loc ) ) { $lo = $mid + 1 }
        else                                        { $hi = $mid }
    }
    return $lo;
}

sub _before ( $at, $loc ) {
    return $at->[0] < $loc->[0] || ( $at->[0] == $loc->[0] && $at->[1] < $loc->[1] );
}

# One pass over the document, cached until a different document is passed:
# - declarations: by symbol ('$x'), then by the refaddr of the block,
#   document or compound statement it belongs to, the declarations in
#   document order as { elem, statement, at } (see
#   Puff::LexicalScopes::declarations), at being the location;
# - assigned: by name, then by the refaddr of the enclosing block or
#   document, the qualifying assignment statements in document order as
#   { elem, at };
# - qualifying: the refaddrs of the symbols those statements assign;
# - writes: by name, the number of other writes, through `$x`, `${x}` or
#   `$main'x`. A write to a qualified name ($main::x, $::x) also counts for
#   its last component, which may be an `our` variable.
sub _analysis ($doc) {
    return $cached if $cached_doc && refaddr($cached_doc) == refaddr($doc);
    $cached_doc = $doc;
    weaken($cached_doc);
    my %data = map { $_ => {} } qw( declarations assigned qualifying writes );
    my %changed;
    for my $token ( $doc->tokens ) {
        for my $decl ( declarations($token) ) {
            push @{ $data{declarations}{ $decl->{symbol} }{ refaddr $decl->{scope} } },
                { elem => $decl->{elem}, statement => $decl->{statement}, at => $decl->{elem}->location };
        }
        $changed{ refaddr $_ } = 1 for $token->isa('PPI::Token::Word') ? _builtin_args($token) : ();
        my ( $name, $last ) = _scalar($token) or next;
        if ( $last == $token && ( my $stmt = _pattern_assignment($token) ) ) {
            push @{ $data{assigned}{$name}{ refaddr $stmt->parent } }, { elem => $stmt, at => $stmt->location };
            $data{qualifying}{ refaddr $token } = 1;
        }
        elsif ( $changed{ refaddr $token } || _is_write( $token, $last ) ) {
            $data{writes}{$name}++;
            $data{writes}{$1}++ if $name =~ /::(\w+)\z/;
        }
    }
    return $cached = \%data;
}

# The name of the plain scalar that starts at $token, with `'` package
# separators made `::`, and its last element: $token itself for `$x`, the
# block for `${x}`. Empty for anything else.
sub _scalar ($token) {
    my ( $name, $last ) = ( undef, $token );
    if ( $token->isa('PPI::Token::Symbol') ) {
        $name = substr $token->content, 1 if $token->content =~ /\A\$/;
    }
    elsif ( $token->isa('PPI::Token::Cast') && $token->content eq '$' ) {
        $last = $token->snext_sibling;
        my @stmt = $last && $last->isa('PPI::Structure::Block') ? $last->schildren    : ();
        my @word = @stmt == 1                                   ? $stmt[0]->schildren : ();
        $name = $word[0]->content if @word == 1 && $word[0]->isa('PPI::Token::Word');
    }
    $name =~ s/'/::/g if defined $name;
    return defined $name && $name =~ /\A(?:::)?\w+(?:::\w+)*\z/ ? ( $name, $last ) : ();
}

# The statement, if $symbol is a plain scalar assigned a pattern by a whole
# statement in a block or the document: `[my|our|state|local] $x =
# qr/.../;`, `$x = quotemeta(...);` or `$x = quotemeta EXPR;`, with nothing
# else on the right-hand side. An assignment inside a condition is not one.
sub _pattern_assignment ($symbol) {
    my $stmt = $symbol->parent;
    return unless $stmt->isa('PPI::Statement') && _is_scope_body( $stmt->parent );
    my $prev = $symbol->sprevious_sibling;
    return if $prev && !( $prev->isa('PPI::Token::Word') && $prev->content =~ /\A(?:my|our|state|local)\z/ );
    return if $prev && $prev->sprevious_sibling;
    my $op = $symbol->snext_sibling;
    return unless $op && $op->isa('PPI::Token::Operator') && $op->content eq '=';
    my $first = $op->snext_sibling or return;
    my @rhs   = ($first);
    while ( my $next = $rhs[-1]->snext_sibling ) { push @rhs, $next }
    pop @rhs if $rhs[-1]->isa('PPI::Token::Structure') && $rhs[-1]->content eq ';';
    return _is_pattern(@rhs) ? $stmt : undef;
}

sub _is_scope_body ($elem) {
    return $elem && ( $elem->isa('PPI::Structure::Block') || $elem->isa('PPI::Document') );
}

# An assignment operator: =, .=, ||=, //=, x= and the like.
my $ASSIGN = qr{\A(?:\*\*|\|\||//|&&|<<|>>|[-+*/.x%&|^])?=\z};

# Builtins that change their arguments, with how many leading arguments
# they change: chomp and chop all, read the buffer after the handle (the
# handle is counted too, which errs towards reporting).
my %CHANGES_ARGS = ( chomp => ~0, chop => ~0, open => 1, opendir => 1, read => 2, recv => 2, sysread => 2 );

# Whether the scalar from $first to $last (`$x`, or `${x}`) is written:
# assigned with any assignment operator (alone or as an element of a list
# on the left), incremented or decremented, localized, aliased by foreach,
# referenced with `\`, or changed by s/// or tr/// (without /r), alone or
# in parentheses. A builtin in %CHANGES_ARGS is handled by _builtin_args.
sub _is_write ( $first, $last ) {
    my $step = qr/\A(?:\+\+|--)\z/;
    return 1
        if _is_token( $first->sprevious_sibling, 'Operator', $step )
        || _is_token( $last->snext_sibling, 'Operator', $step );
    my $target = $first;
    my $prev   = $first->sprevious_sibling;
    my $list   = $first->parent->parent;
    if ( $list && $list->isa('PPI::Structure::List') && ( !$prev || _is_token( $prev, 'Operator', ',' ) ) ) {
        $target = $list;                        # ($x, $y) = ..., local ($x), for ($x), \($x)
        $prev   = $target->sprevious_sibling;

        # for my $v ($x)
        $prev = $prev->sprevious_sibling if $prev && $prev->isa('PPI::Token::Symbol');
    }
    return 1 if _is_token( $prev, 'Word', 'local' ) || _is_token( $prev, 'Cast', '\\' );
    $prev = $prev->sprevious_sibling if _is_token( $prev, 'Word', qr/\A(?:my|our|state)\z/ );
    return 1 if _is_token( $prev, 'Word', qr/\Afor(?:each)?\z/ );

    for my $el ( $last, $target ) {
        my $op = $el->snext_sibling;
        return 1 if _is_token( $op, 'Operator', $ASSIGN );
        next unless _is_token( $op, 'Operator', qr/\A[=!]~\z/ );
        my $re = $op->snext_sibling;
        next
            unless $re
            && ( $re->isa('PPI::Token::Regexp::Substitute') || $re->isa('PPI::Token::Regexp::Transliterate') );
        my %mod = $re->get_modifiers;
        return 1 unless $mod{r};
    }
    return 0;
}

# The scalars (their first token) that $word changes when it is a builtin in
# %CHANGES_ARGS called as a function, not a method: its direct arguments
# among the leading ones it changes, as in `chomp $x`, `chomp($x, $y)`,
# `open my $fh` or `read $fh, $x, 10`. The arguments are walked forwards
# lazily, stopping at the end of the list or at a list operator such as
# another of these builtins, which takes the rest of the list itself, so
# the cost is linear in the document even for `(chomp, chomp, ...)`. A
# comma right after the builtin means it has no arguments. A scalar inside
# a nested call (`chomp(foo $x)`) is not a direct argument.
sub _builtin_args ($word) {
    my $changes = $CHANGES_ARGS{ $word->content } or return;
    return if _is_token( $word->sprevious_sibling, 'Operator', '->' );
    my $comma = qr/\A(?:,|=>)\z/;
    my $el    = $word->snext_sibling;
    my ( $inline, @args ) = (1);
    if ( $el && $el->isa('PPI::Structure::List') ) {
        @args   = $el->schildren;
        @args   = $args[0]->schildren if @args == 1 && $args[0]->isa('PPI::Statement');
        $el     = shift @args;
        $inline = 0;
    }
    elsif ( _is_token( $el, 'Operator', $comma ) ) {
        return;
    }
    my ( $index, $start, @changed ) = ( 0, 1 );
    while ($el) {
        if ( _is_token( $el, 'Operator', $comma ) ) {
            last if ++$index >= $changes;
            $start = 1;
            next;
        }
        last if $el->isa('PPI::Token::Structure') || _is_token( $el, 'Operator', qr/\A(?:or|and|xor|not)\z/ );
        if ( $el->isa('PPI::Token::Word') ) {
            last if $CHANGES_ARGS{ $el->content };
            next if $start && $el->content =~ /\A(?:my|our|state|local)\z/;
            my $next = $el->snext_sibling;

            # A bareword handle (`read FH, $x`) or a call in parentheses is
            # one argument; any other word takes the rest of the list.
            last
                unless $next
                && ( _is_token( $next, 'Operator', qr/\A(?:,|=>)\z/ ) || $next->isa('PPI::Structure::List') );
        }
        push @changed, $el if $start && _scalar($el);
        $start = 0;
    }
    continue {
        $el = $inline ? $el->snext_sibling : shift @args;
    }
    return @changed;
}

# Whether $elem is a PPI::Token::$type whose content is $content, or matches
# it when it is a regex.
sub _is_token ( $elem, $type, $content ) {
    return 0 unless $elem && $elem->isa("PPI::Token::$type");
    return ref $content ? $elem->content =~ $content : $elem->content eq $content;
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
C<\Q>, C<\L>, C<\U> and C<\F> (each ended by its own C<\E>, except that a
C<\L>, C<\U> or C<\F> ends an active one and any C<\Q> after it, as in
Perl), C<$> as an
anchor before C<)>, C<|>, whitespace or the end, code blocks such as
C<(?{ ... })> and C<(??{ ... })>, character classes, C<#> comments under C</x>, and a C<{...}>
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

a plain scalar whose nearest declaration visible from the regex is a whole
statement C<my $x = qr/.../;> or C<my $x = quotemeta(...);> /
C<quotemeta EXPR;> (or C<our>, C<state>), with nothing else on the
right-hand side. The enclosing blocks are searched from the innermost
outwards for the latest declaration of the name before the regex; C<my>,
C<our> and C<state> (list forms included), a C<for my $v> loop variable
(owned by its loop) and a sub signature parameter (owned by the sub's body)
all count. An inner C<my $x = shift>, C<for my $x (...)>, C<sub f ($x)> or
C<my ($x) = @_> therefore hides an outer C<my $x = qr/.../>. A global with
no declaration needs a qualifying C<$x = qr/.../;> (or
C<local $x = qr/.../;>) statement before the
regex in the same or an enclosing block (or the file).

In both cases the name must have no other write anywhere in the file: any
assignment operator after it (C<=>, C<.=>, C<||=>, C<//=> and so on, alone
or in a list on the left), C<local $x> other than a qualifying C<local $x = qr/.../;>, a
C<foreach> loop variable of that
name or a C<foreach> list holding it, a reference C<\$x>, C<$x++>,
C<$x-->, C<++$x> or C<--$x>, C<chomp> or C<chop> of it, C<$x> as the
handle of C<open> or C<opendir> or the buffer of C<read>, C<recv> or
C<sysread> (as a direct argument of the builtin: C<< $o->open($x) >> and
C<chomp(foo $x)> do not count), or C<$x =~ s///>, C<($x) =~ s///> or
C<tr///> (without C</r>).
This is by name, not by scope, so a same-named variable written in another
sub (or package) also counts. A write to a package-qualified name
(C<$main::x>, C<$::x>, C<${main::x}>, C<$main'x>) counts for the last
component of the name, and a write to C<$x> counts for a qualified
C<$main::x>. Writes the rule does not recognise are missed: an alias
through C<@_> in a sub call, the C<$_> of C<map> or C<grep>, a glob
assignment, or a symbolic name (C<${'main::x'}>, C<$::{x}>). An assignment inside a condition
(C<if (my $x = qr/a/)>) is not seen as qualifying, which errs towards
reporting. C<$x = $opt{x} // qr/,/>, C<$x ||= qr/,/> and
C<join '|', map {quotemeta} @w> are reported;

=item *

capture and punctuation variables (C<$1>, C<$&>, C<$^N>, C<${^MATCH}>,
C<$+{name}>), as the issue that added the rule asked, since a capture is
usually a substring of the string being matched; C<$#x>; arrays; and a
scalar in the code of C<@{[ ... ]}> that is inside the argument of
C<quotemeta> (only the variable right after C<quotemeta> without
parentheses) or inside a C<\Q...\E> there. The other scalars in
C<@{[ ... ]}>, such as C<$y> in C<@{[ $y . quotemeta $x ]}>, are reported,
with no fix, as the code is Perl rather than pattern text. The code is
scanned as text, not parsed: a bracket, C<quotemeta> or C<\Q> inside a
string literal in it is taken as code, so C<@{[ '\Q' . $x ]}> hides C<$x>.

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
