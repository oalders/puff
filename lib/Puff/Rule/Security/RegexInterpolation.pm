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
        expression). Input such as `(a+)+$` can also make the match take
        exponential time (CWE-1333, inefficient regular expression
        complexity). `\Q$var\E` (or `quotemeta`) matches the value as
        literal text.

        The rule reports a scalar variable (`$x`, `${x}`, `$$x`,
        `$x->{k}`, `$h{k}`, `$x->[0]` and the like) interpolated into the
        pattern of `m//`, `//`, `s///`, `qr//` or a `split` regex, outside
        `\Q...\E`. It does not report:

        - the replacement side of `s///`;
        - a pattern with `'` delimiters (`m'...'`), which does not
          interpolate;
        - a variable inside `\Q...\E`, or after a `\Q` with no `\E`;
        - a variable whose name looks like a regex: `re`, `rx`, `regex`,
          `regexp`, `pattern` or `pat` as a whole word of the name
          (`$re`, `$re_word`, `$word_rx`, `$pats`), or `regex` or
          `pattern` anywhere in it. A constant hash key counts too, as in
          `$self->{pattern}`;
        - a plain scalar assigned anywhere in the file from an expression
          containing a `qr//` or `quotemeta`. This ignores scope: any
          variable of that name in the file is skipped;
        - a plain scalar whose name starts with a capital letter (`$WS`,
          `$DateTime`): by convention a package-wide constant or global,
          usually a pattern built once (often in another module);
        - regex and other punctuation variables (`$&`, `$1`, `$^N`,
          `${^MATCH}`), `$` used as an anchor (`/foo$/`, `/(a$)/`) and
          code blocks (`(?{ ... })`);
        - arrays (`@x`, `@{[ ... ]}`): an interpolated array is joined
          with spaces and is rarely user input.

        A pattern held in a variable and matched directly (`$s =~ $x`) or
        a string passed to `split` is not reported.

        The unsafe fix wraps the variable, with its subscripts, in
        `\Q...\E`. It changes what the regex matches when the variable is
        meant to hold a pattern, which is why the fix is unsafe and the
        rule is opt-in. There is no fix when the extent of the variable is
        uncertain: `${ expr }`, a `[` right after the name (Perl guesses
        whether it starts a subscript or a character class), postfix
        dereference, an old-style `'` package separator or a trailing `::`
        after the name, an unclosed subscript, or a delimiter other than
        common punctuation.

        This rule is selected only by its code or `ALL`, not by `S`.
        END
}

# Delimiters whose patterns the fix rewrites. Others (a letter, `$`, `@`,
# `-` and the like) make the extent of a variable uncertain.
my %FIX_DELIM = map { $_ => 1 } split //, '/{([<!|#,~%^;:=+?"';

my $REGEX_NAME = qr/(?:\A|_)(?:re|rx|regexp?|pattern|pat)(?:_|\z|s\z)|regex|pattern/i;

# A capitalised name such as $WS, $CRLF or $DateTime: by convention a
# package-wide constant or global, usually a pattern built once, rather than
# input.
my $CONSTANT_NAME = qr/\A[A-Z]/;

# A quantifier such as {2}, {2,} or {2,5} after a variable, rather than a
# hash subscript.
my $QUANTIFIER = qr/\G\{\s*(?:\d+\s*(?:,\s*\d*\s*)?|,\s*\d+\s*)\}/;

sub check ( $self, $elem, $doc ) {
    my @violations;
    for my $found ( _findings( $elem, $doc ) ) {
        push @violations, Puff::Violation->new(
            rule    => $self,
            code    => $self->code,
            element => $elem,
            line    => $found->{line},
            column  => $found->{column},
            message =>
                "$found->{text} interpolated into a regex without \\Q...\\E; metacharacters in it change the match",
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
# offset (in the token's content), line, column, fixable }.
sub _findings ( $elem, $doc ) {
    my $section = $elem->{sections} && $elem->{sections}[0] or return;
    my $open    = substr $section->{type}, 0, 1;
    return if $open eq q{'};

    my $pattern = substr $elem->content, $section->{position}, $section->{size};
    my $skip    = _skipped_names($doc);
    my $loc     = $elem->location or return;
    my @found;
    for my $var ( _variables($pattern) ) {
        next if grep { $_ =~ $REGEX_NAME } @{ $var->{names} };
        if ( defined $var->{name} && !$var->{subscripted} && !$var->{deref} ) {
            next if $skip->{ $var->{name} } || $var->{names}[0] =~ $CONSTANT_NAME;
        }
        my $offset = $section->{position} + $var->{start};
        my $before = substr $elem->content, 0, $offset;
        my $nl     = () = $before =~ /\n/g;
        push @found, {
            text    => $var->{text},
            offset  => $offset,
            line    => $loc->[0] + $nl,
            column  => $nl                                  ? length( $before =~ s/.*\n//sr ) + 1 : $loc->[1] + $offset,
            fixable => $var->{certain} && $FIX_DELIM{$open} ? 1                                   : 0,
        };
    }
    return @found;
}

# Scans a pattern as Perl interpolates it and returns the scalar variables
# outside \Q...\E: { start, text, name, names, subscripted, deref, certain }.
sub _variables ($pattern) {
    my ( @found, @case );
    pos($pattern) = 0;
    while ( pos($pattern) < length $pattern ) {
        if ( $pattern =~ /\G\\([QLUF])/gc ) { push @case, $1; next }
        if ( $pattern =~ /\G\\E/gc )        { pop @case;      next }
        next if $pattern =~ /\G\\c./gcs || $pattern =~ /\G\\./gcs;

        # Code blocks hold Perl code, not interpolation.
        if ( $pattern =~ /\G\((?:\?\??|\*)(?=\{)/gc ) { _skip_brackets( \$pattern ); next }

        # Arrays and @{[ ... ]} are not reported, nor what is inside them.
        if ( $pattern =~ /\G\@(?=\{)/gc ) { _skip_brackets( \$pattern ); next }
        next if $pattern =~ /\G\@\$*(?:::)?\w+(?:::\w+)*/gc;

        my $start = pos $pattern;
        if ( $pattern =~ /\G\$(?=[()| \r\n\t]|\z)/gc ) {next}    # an anchor
        if ( $pattern =~ /\G\$/gc ) {
            my $var = _variable( \$pattern, $start );
            push @found, $var if $var && !grep { $_ eq 'Q' } @case;
            next;
        }
        pos($pattern)++;
    }
    return @found;
}

# The variable whose `$` is at $start (pos is just after it), or undef for a
# punctuation variable. Leaves pos after the variable.
sub _variable ( $ref, $start ) {
    my %var = ( start => $start, names => [], certain => 1 );
    if ( $$ref =~ /\G\#/gc ) {    # $#x, $#{x}, $#$x: not a scalar
        _skip_brackets($ref) if $$ref =~ /\G(?=\{)/;
        $$ref =~ /\G\$*\w+/gc;
        return;
    }

    # Lookaheads below match without /g: a zero-length /gc match right
    # after another at the same position always fails.
    $var{deref} = $$ref =~ /\G(\$+)/gc ? length $1 : 0;

    if ( $$ref =~ /\G\{\s*\^\w+\s*\}/gc ) {return}                      # ${^MATCH}
    if ( $$ref =~ /\G\{\s*((?:::)?[A-Za-z_]\w*(?:::\w+)*)\s*\}/gc ) {
        $var{name} = $1;
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
    push @{ $var{names} }, $var{name} =~ s/.*:://r if defined $var{name};

    while (1) {
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
        my $key_start = pos $$ref;
        _skip_brackets($ref) or $var{certain} = 0;
        my $key = substr $$ref, $key_start, pos($$ref) - $key_start;
        push @{ $var{names} }, $1 if $key =~ /\A\{\s*['"]?(\w+)['"]?\s*\}\z/;
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

# Names of plain scalars assigned, anywhere in the document, from an
# expression with a qr// or quotemeta in it.
sub _skipped_names ($doc) {
    return $cached if $cached_doc && refaddr($cached_doc) == refaddr($doc);
    $cached_doc = $doc;
    weaken($cached_doc);
    my %skip;
    for my $symbol ( @{ $doc->find('PPI::Token::Symbol') || [] } ) {
        next unless $symbol->content =~ /\A\$((?:::)?\w+(?:::\w+)*)\z/;
        my $name = $1;
        my $op   = $symbol->snext_sibling;
        next unless $op && $op->isa('PPI::Token::Operator') && $op->content =~ /\A(?:=|\|\|=|\/\/=)\z/;
        for ( my $el = $op->snext_sibling ; $el ; $el = $el->snext_sibling ) {
            last if $el->isa('PPI::Token::Structure') && $el->content eq ';';
            if ( _quotes_pattern($el) ) { $skip{$name} = 1; last }
        }
    }
    return $cached = \%skip;
}

sub _quotes_pattern ($el) {
    my $is = sub ( $, $e ) {
        return $e->isa('PPI::Token::QuoteLike::Regexp')
            || ( $e->isa('PPI::Token::Word') && $e->content eq 'quotemeta' );
    };
    return 1 if $is->( undef, $el );
    return $el->isa('PPI::Node') && $el->find_first($is) ? 1 : 0;
}

1;

# ABSTRACT: S019 - variable interpolated into a regex without \Q

__END__

=pod

=head1 DESCRIPTION

Reports a scalar variable interpolated into the pattern of C<m//>, C<//>,
C<s///>, C<qr//> or a C<split> regex outside C<\Q...\E>. Metacharacters in
the variable's value change what the pattern matches (CWE-625), and a
crafted value can make the match very slow (CWE-1333). The violation is
reported at the variable, so a regex with two such variables has two.

The pattern is scanned the way Perl interpolates it: backslash escapes,
C<\Q>, C<\L>, C<\U> and C<\F> (each ended by its own C<\E>), C<$> as an
anchor before C<)>, C<|>, whitespace or the end, code blocks such as
C<(?{ ... })>, and a C<{...}> after a variable that is a quantifier rather
than a subscript. The replacement of C<s///> and patterns with C<'>
delimiters are not looked at.

Not reported, as deliberate patterns or not input:

=over

=item *

a name with C<re>, C<rx>, C<regex>, C<regexp>, C<pattern> or C<pat> as a
whole C<_>-separated word, or plural (C<$re>, C<$word_rx>, C<$pats>), or with
C<regex> or C<pattern> anywhere in it; a constant hash key is checked
too (C<< $self->{pattern} >>);

=item *

a plain scalar whose name starts with a capital letter (C<$WS>,
C<$DateTime>), by convention a package-wide constant or global, usually a
pattern built once, often in another module;

=item *

a plain scalar assigned anywhere in the file (C<=>, C<||=> or C<//=>) from
an expression containing a C<qr//> or C<quotemeta>. This is deliberately
simple: it ignores scope, so any variable of that name in the file is
skipped;

=item *

punctuation and regex variables (C<$1>, C<$&>, C<$^N>, C<${^MATCH}>),
C<$#x>, and arrays, including C<@{[ ... ]}>. An array is joined with
spaces, and is rarely the input this rule is about.

=back

The unsafe fix wraps the variable and its subscripts in C<\Q...\E>. When the
variable was meant to hold a pattern the fix changes what the regex matches,
which is why the fix is unsafe and why the rule is selected only by its
exact code (C<S019>) or C<ALL>. No fix is offered when the extent of the
variable in the pattern is uncertain: C<${ expr }>, a C<[> right after
the name (Perl guesses whether it starts a subscript or a character
class), postfix dereference, a C<'> or trailing C<::> after the
name, an unclosed subscript, or a delimiter other than common punctuation.

Matching against a variable directly (C<$s =~ $x>) and a string pattern
given to C<split> are not reported.

=cut
