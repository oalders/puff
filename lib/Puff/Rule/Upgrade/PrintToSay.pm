package Puff::Rule::Upgrade::PrintToSay;

use v5.36;
use parent 'Puff::Rule';

use Scalar::Util qw( refaddr );
use version      ();

use Puff::PPIUtil qw( call_args is_builtin_call );

sub code       {'U002'}
sub summary    {'print with a trailing newline can be say'}
sub applies_to {'PPI::Token::Word'}
sub fix_safety {'safe'}

sub options {
    return { modules => [ 'Modern::Perl', 'Mojo::Base', 'Mojolicious::Lite', 'common::sense' ] };
}

sub explanation {
    return <<~'END';
        When the `say` feature is on, `say` prints its arguments followed by
        a newline, so a `print` whose last argument ends in `\n` can drop the
        newline and say what it means:

            use v5.36;
            say "hello";
            say $fh "x: $x";

        The rule only reports a `print` when `say` is known to be enabled at
        that point: an earlier `use v5.10` or later (`use 5.010`,
        `use 5.10.0`), `use feature 'say'`, `use feature ':5.10'` or a later
        bundle, `use feature ':all'`, or `use` of a module in the `modules`
        option, in the same or an enclosing block. A later `use VERSION`
        below 5.10 turns it off again. A file with `no feature` naming
        `say`, `:all` or a bundle, or with no arguments, is not checked.

        Option `modules` (default `["Modern::Perl", "Mojo::Base",
        "Mojolicious::Lite", "common::sense"]`): modules whose `use` enables
        `say` in the caller. `use Module ()` does not count.

        The last argument must be a single double-quoted or `qq` string
        that ends in the escape `\n` (`"\\n"` ends in a backslash and `n`,
        and is not reported). `print $fh ...`, `print {$fh} ...`,
        `print STDERR ...` and `print(...)` are handled. `print "\n"` is
        reported and becomes `say ""`. Not reported: single-quoted strings,
        heredocs, a newline written as `\x0a`, `\012` or `\N{...}`, strings
        with `\Q` or `\c`, `print $a, "\n"` where the newline is a separate
        argument, a last argument that is an expression (`"a\n" x 3`,
        `$ok ? "y\n" : "n\n"`), `CORE::print`, method calls such as
        `$fh->print(...)` and `print =>`. Nor is a string where it is not
        clear that the `\n` is a newline: in `"a$\n"` and `"a$ \n"` the
        `$\` is the variable, followed by an `n`. So a string is skipped
        if, before its final `\n`, it has `$\`, `@$`, `@\`, or a `$` or `@`
        followed by white space; if an odd run of backslashes comes just
        before the `\n`; if a `$` and one other non-word character other
        than `$` or `@` come just before it (`"a$^\n"` is `$^\` and `n`); or
        if a `$` or `@` comes just before it, except `$$` or `$@` after a
        character other than `$`, `@` or `\`. So `"pid $$\n"` and `"$@\n"`
        are reported, but `"a\$\n"`, `"a@\n"`, `"a$:\n"` and `"$$$\n"` are
        not, though some of them do end in a newline.
        A `qq` whose delimiter is a letter, digit or `_`
        (`qq n a\nn`) is skipped. `use if ..., feature => 'say'` is not
        recognised, so code that enables `say` that way is not checked.

        The fix replaces `print` with `say` and removes the trailing `\n`
        from the string, keeping its quotes. It is safe, except that `say`
        always ends the output with "\n" where `print` adds `$\`. So the
        violation has no fix when the file's text contains `$\`,
        `$OUTPUT_RECORD_SEPARATOR`, `$ORS` or `output_record_separator`
        anywhere, even in a string, regex, heredoc or comment (but not `$$\`,
        as in `"pid $$\n"`); mentions the globs `*\`, `*ORS` and
        `*OUTPUT_RECORD_SEPARATOR`, or `$ \` with a space; has a `#!` line
        with an `-l` switch, or
        has a symbolic `${...}` or `*{...}` that is not one of two shapes
        taken to be safe. One is a scalar variable, with optional
        subscripts that have no backslash or ORS name in them (`${$ref}`,
        `${ $self->{x} }`), when strict refs appears to be in effect, so the
        variable should hold a reference: a top-level `use strict` (bare or
        naming `refs`) or `use v5.12` or later comes first, and the file
        has no `no strict` and no `use VERSION` below 5.12. Without that,
        `${$name}` and `$$name` may name `$\`, so the fix is withheld. The
        other is strings and scalar variables joined with `.`, with no
        backslash, whose text ends in a literal `::name` other than `ORS`
        or `OUTPUT_RECORD_SEPARATOR` (`*{"${class}::foo"}`). Anything else,
        such as `${"\\"}`, `${ chr(92) }` or `${ "main::" . $name }`, has
        no fix. Not seen: a `$\` set in another file or module; stash
        access (`$::{"\\"}`) and glob slots (`*{$glob}{SCALAR}`, with a glob
        from `Symbol::qualify_to_ref`); method names built at run time
        (`STDOUT->can("output_" . "record_separator")`, `STDOUT->$m(...)`);
        strict refs turned off without a `no strict` statement
        (`BEGIN { strict->unimport('refs') }`, `$^H`, a module's `import`);
        and a `$\` set in a string `eval`.

        Also, `say` passes its newline through `$\`, so a tied handle whose
        `PRINT` ignores `$\` loses the newline. This is a known caveat of
        the fix being labelled safe.
        END
}

sub check ( $self, $elem, $doc ) {
    _last_string($elem) or return;
    return unless $self->_say_enabled( $elem, $doc );
    return $self->violation( $elem, fixable => _sets_ors($doc) ? 0 : 1 );
}

sub fix ( $self, $violation, $fix ) {
    my $word  = $violation->element;
    my $doc   = $word->top;
    my $quote = _last_string($word) or return 0;
    return 0 if _sets_ors($doc) || !$self->_say_enabled( $word, $doc );

    my $src = $fix->source;
    $fix->replace_range( $src->start_of($word), $src->end_of($word), 'say' );

    # The closing delimiter is one character; the `\n` sits just before it.
    my $end = $src->end_of($quote) - 1;
    $fix->replace_range( $end - 2, $end, q{} );
    return 1;
}

# The string that ends a `print` call's argument list, if it qualifies.
sub _last_string ($word) {
    return unless $word->content eq 'print' && is_builtin_call($word);
    my $args = call_args($word);
    return unless @$args;
    my @last = @{ $args->[-1] };
    if ( @last == 2 && @$args == 1 ) {
        return unless _is_filehandle( $last[0] );
        shift @last;
    }
    return unless @last == 1;
    my $quote = $last[0];
    return unless $quote->isa('PPI::Token::Quote::Double') || $quote->isa('PPI::Token::Quote::Interpolate');
    return if $quote->isa('PPI::Token::Quote::Interpolate') && $quote->content =~ /\Aqq\s*\w/;
    my $string = $quote->string;
    return if $string =~ /\\[Qc]/;
    return unless _ends_in_newline($string);
    return if $string eq q{\n} && @$args > 1;    # `print $x, "\n"`
    return unless $quote->content =~ /\\n.\z/s;
    return $quote;
}

# Whether a string's source clearly ends in the escape `\n`. Rather than
# model how perl reads `$`, `@` and `\`, anything unclear counts as no:
# before the `\n`, a `$\`, `@$`, `@\`, or a `$` or `@` followed by white
# space (perl reads `"a$ \n"` as `$\` and `n`); an odd run of backslashes
# just before it; a `$` and one other non-word character just before it
# (perl reads `"a$^\n"` as `$^\` and `n`), except `$$` and `$@`; or a `$`
# or `@` just before it, except `$$` or `$@` after a character that is not
# `$`, `@` or `\`. Each check is linear.
sub _ends_in_newline ($string) {
    return 0 unless length $string >= 2 && substr( $string, -2 ) eq '\\n';
    my $body = substr $string, 0, -2;
    return 0 if $body =~ /[\$\@]\s|\$\\|\@[\$\\]/;
    return 0 if $body =~ /\$[^\w\$\@]\z/;
    my ($slashes) = reverse($body) =~ /\A(\\*)/;
    return 0 if length($slashes) % 2;
    return 1 unless $body =~ /[\$\@]\z/;
    return $body =~ /(?:\A|[^\$\@\\])\$[\$\@]\z/ ? 1 : 0;
}

sub _is_filehandle ($elem) {
    return 1 if $elem->isa('PPI::Structure::Block');
    return 1 if $elem->isa('PPI::Token::Symbol') && $elem->raw_type eq '$';
    return 1 if $elem->isa('PPI::Token::Word')   && $elem->content =~ /\A[A-Z_][A-Z0-9_]*\z/;
    return 0;
}

my $MIN = version->parse('v5.10.0');

# Whether a statement earlier in this or an enclosing block turned `say` on,
# and nothing in the file may have turned it off.
sub _say_enabled ( $self, $word, $doc ) {
    my $includes = $doc->find('PPI::Statement::Include') || [];
    return 0 if grep { _disables($_) } @$includes;

    my %modules = map { $_ => 1 } @{ $self->option('modules') };
    my %scope;
    for ( my $p = $word->parent ; $p ; $p = $p->parent ) { $scope{ refaddr($p) } = 1 }
    my $here    = _position($word);
    my $enabled = 0;
    for my $include (@$includes) {
        next unless $include->type eq 'use';
        next unless $scope{ refaddr( $include->parent ) };
        next unless _before( _position($include), $here );
        if ( my $v = $include->version ) {
            my $parsed = eval { version->parse($v) } or next;
            $enabled = $parsed >= $MIN ? 1 : 0;
        }
        elsif ( ( $include->module // q{} ) eq 'feature' ) {
            $enabled = 1 if grep { _enables_say($_) } _strings($include);
        }
        elsif ( $modules{ $include->module // q{} } && !_empty_import($include) ) {
            $enabled = 1;
        }
    }
    return $enabled;
}

sub _position ($elem) {
    my $loc = $elem->location or return [ 0, 0 ];
    return [ @$loc[ 0, 1 ] ];
}

sub _before ( $x, $y ) {
    return $x->[0] < $y->[0] || ( $x->[0] == $y->[0] && $x->[1] < $y->[1] );
}

sub _enables_say ($name) {
    return 1 if $name eq 'say' || $name eq ':all';
    return 1 if $name =~ /\A:5\.(\d+)(?:\.\d+)?\z/ && $1 >= 10;
    return 0;
}

sub _disables ($include) {
    return 0 unless $include->type eq 'no' && ( $include->module // q{} ) eq 'feature';
    my @names = _strings($include);
    return 1 unless @names;
    return scalar grep { $_ eq 'say' || /\A:/ } @names;
}

# The string arguments of a use/no statement.
sub _strings ($include) {
    my @names;
    for my $token ( @{ $include->find('PPI::Token') || [] } ) {
        if ( $token->isa('PPI::Token::QuoteLike::Words') ) {
            push @names, $token->literal;
        }
        elsif ( $token->isa('PPI::Token::Quote') ) {
            push @names, $token->string;
        }
    }
    return @names;
}

# `use Module ()`, which does not call import.
sub _empty_import ($include) {
    my @parts = $include->schildren;
    splice @parts, 0, 2;
    shift @parts if @parts && $parts[0]->isa('PPI::Token::Number');
    pop @parts if @parts   && $parts[-1]->isa('PPI::Token::Structure') && $parts[-1]->content eq ';';
    return @parts == 1     && $parts[0]->isa('PPI::Structure::List')   && !$parts[0]->schildren;
}

# Whether the output record separator may be set, so that print and say
# end their output differently. The raw text is searched first, so that
# `$\` in code PPI does not tokenise (interpolated `@{[ ]}`, `s///e`,
# `(?{ })`, heredoc bodies) counts. That also matches `"\$\\"` and the
# like, which only loses a fix. A `$\` after another `$` is skipped: perl
# reads `$$\` as `$$` then `\`, as in `"pid $$\n"`.
sub _sets_ors ($doc) {
    return 1 if $doc->serialize =~ /(?<!\$)\$\\|\$(?:ORS|OUTPUT_RECORD_SEPARATOR)\b|output_record_separator/;
    my $first     = $doc->first_token;
    my $strict_at = _strict_refs_at($doc);
    return 1 if $first && $first->isa('PPI::Token::Comment') && $first->content =~ /\A#!.*\s-\S*l/;
    return 1 if $doc->find_first(
        sub {
            my $elem = $_[1];
            return 1
                if $elem->isa('PPI::Token::Symbol')
                && $elem->content =~ /\A[\$*](?:\w+::)*(?:ORS|OUTPUT_RECORD_SEPARATOR)\z/;

            # `*\` and `*main::\` parse as `*` or `*main::` followed by `\`.
            if ( $elem->isa('PPI::Token::Cast') && $elem->content eq '\\' ) {
                my $prev = $elem->previous_token;
                return 1
                    if $prev
                    && ( ( $prev->isa('PPI::Token::Operator') && $prev->content eq '*' )
                    || ( $prev->isa('PPI::Token::Symbol') && $prev->content =~ /\A\*(?:\w+::)+\z/ ) );
            }

            # `$ \` with a space parses as two casts. A symbolic `${"\\"}` or
            # `*{"main::ORS"}` counts, as does any name not taken to be safe.
            # Without strict refs, `$$name` or `${$name}` may hold the name.
            if ( $elem->isa('PPI::Token::Cast') && $elem->content =~ /\A[\$*]\z/ ) {
                my $next   = $elem->snext_sibling;
                my $strict = $strict_at && _before( $strict_at, _position($elem) );
                return 1 unless $next;
                return 1 if $elem->content eq '$' && $next->isa('PPI::Token::Cast') && $next->content eq '\\';
                return _names_ors( $next, $strict ) if $next->isa('PPI::Structure::Block');
                return 1 unless $strict;
            }
            return 0;
        }
    );
    return 0;
}

# Whether a deref block's name may be the output record separator. Only
# two shapes are taken not to be: under strict refs, a scalar variable with
# optional subscripts (`${$ref}`, `${ $self->{x} }`), which must then hold
# a reference; and strings and scalar variables joined with `.` whose text
# ends in a literal `::name` other than ORS (`*{"${class}::foo"}`).
# Anything else counts.
sub _names_ors ( $block, $strict ) {
    my @parts = _block_parts($block) or return 1;
    return 0 if $strict && _is_variable(@parts);
    return 0 if _is_named(@parts);
    return 1;
}

my $STRICT_MIN = version->parse('v5.12.0');

# Where strict refs appears to be on for the rest of the file: the first
# top-level `use strict` (bare, or naming `refs`) or `use v5.12` or later.
# Undef if the file has any `no strict`, or a `use VERSION` below 5.12,
# which may turn implicit strict off.
sub _strict_refs_at ($doc) {
    my $at;
    for my $include ( @{ $doc->find('PPI::Statement::Include') || [] } ) {
        my $module = $include->module // q{};
        return if $include->type eq 'no' && $module eq 'strict';
        next unless $include->type eq 'use';
        my $on;
        if ( my $v = $include->version ) {
            my $parsed = eval { version->parse($v) } or return;
            return if $parsed < $STRICT_MIN;
            $on = 1;
        }
        elsif ( $module eq 'strict' ) {
            my @names = _strings($include);
            $on = !@names || grep { $_ eq 'refs' } @names;
            $on = 0 if !@names && _has_args($include);
        }
        next unless $on && refaddr( $include->parent ) == refaddr($doc);
        $at //= _position($include);
    }
    return $at;
}

# Whether a use/no statement has anything after the module name.
sub _has_args ($include) {
    my @parts = $include->schildren;
    splice @parts, 0, 2;
    pop @parts if @parts && $parts[-1]->isa('PPI::Token::Structure') && $parts[-1]->content eq ';';
    return scalar @parts;
}

# The significant parts of a block holding a single statement.
sub _block_parts ($block) {
    my @statements = $block->schildren;
    return unless @statements == 1;
    my @parts = $statements[0]->schildren;
    pop @parts if @parts && $parts[-1]->isa('PPI::Token::Structure') && $parts[-1]->content eq ';';
    return @parts;
}

# A scalar variable, then subscripts with no backslash or ORS name in them.
sub _is_variable ( $first, @rest ) {
    return 0 unless $first->isa('PPI::Token::Symbol') && $first->raw_type eq '$';
    for my $part (@rest) {
        next if $part->isa('PPI::Token::Operator') && $part->content eq '->';
        return 0 unless $part->isa('PPI::Structure::Subscript');
        return 0 if $part->content =~ /\\|ORS|OUTPUT_RECORD_SEPARATOR/;
        return 0 if $part->find_first('PPI::Token::HereDoc');
    }
    return 1;
}

# Strings and scalar variables joined with `.`, whose text ends in a
# literal `::name`. The literal parts are joined first, so that
# `"main::O" . "RS"` is seen as naming ORS.
sub _is_named (@parts) {
    return 0 unless @parts % 2;
    my $text = q{};
    for my $i ( 0 .. $#parts ) {
        my $part = $parts[$i];
        if ( $i % 2 ) {
            return 0 unless $part->isa('PPI::Token::Operator') && $part->content eq '.';
        }
        elsif ( $part->isa('PPI::Token::Quote') ) {
            $text .= $part->string;
        }
        elsif ( $part->isa('PPI::Token::Symbol') && $part->raw_type eq '$' ) {
            $text .= "\0";
        }
        else {
            return 0;
        }
    }
    return 0 if $text =~ /\\/;

    # In `"$x::foo"` the `::foo` is part of the variable's name.
    my ( $before, $name ) = $text =~ /([\$\@]?)[\w:']*::(\w+)\z/ or return 0;
    return !$before && $name ne 'ORS' && $name ne 'OUTPUT_RECORD_SEPARATOR';
}

1;

# ABSTRACT: U002 - print with a trailing newline can be say

__END__

=pod

=head1 DESCRIPTION

Reports C<print> whose last argument is a double-quoted or C<qq> string
ending in C<\n>, when the C<say> feature is known to be enabled at that
point. The safe fix replaces C<print> with C<say> and drops the trailing
C<\n>:

    use v5.36;
    print "hello\n";        # say "hello";
    print $fh "x: $x\n";    # say $fh "x: $x";

C<say> counts as enabled after C<use v5.10> or later (also C<use 5.010> and
C<use 5.10.0>), C<use feature 'say'>, C<use feature ':5.10'> or a later
bundle, C<use feature ':all'>, or C<use> of a module named in the
C<modules> option, when that statement comes earlier in the same block or an
enclosing one. A later C<use VERSION> below 5.10 in scope turns it off.

=head2 Options

=over 4

=item modules

Modules that enable C<say> in the code that uses them. Default:
L<Modern::Perl>, L<Mojo::Base>, L<Mojolicious::Lite> and L<common::sense>.
C<use Module ()> does not count, since it skips C<import>.

    [rules.U002]
    modules = ["Modern::Perl", "Mojo::Base", "My::Boilerplate"]

=back

Edge cases:

=over 4

=item *

A file with C<no feature> that names C<say>, C<:all> or any bundle, or that
has no arguments, is not checked at all, wherever that statement is.

=item *

C<print "\n"> is reported and fixed to C<say "">. A string ending in
C<\n\n> loses only its last C<\n>. C<"\\n"> ends in a backslash and an
C<n>, not a newline, and is not reported.

=item *

Not reported: single-quoted strings (C<'\n'> is not a newline), heredocs,
a newline written as C<\x0a>, C<\012> or C<\N{...}>, strings containing
C<\Q> or C<\c>, C<print $a, "\n"> with the newline as its own argument, a
last argument that is an expression rather than a lone string,
C<CORE::print>, method calls such as C<< $fh->print >>, and C<< print => >>.

=item *

A string is not reported unless its final C<\n> is clearly a newline. In
C<"a$\n"> and C<"a$ \n"> the C<$\> is a variable followed by an C<n>, and
dropping the C<\n> would not compile. Rather than model how perl reads
C<$>, C<@> and C<\>, the rule skips a string that, before its final
C<\n>, has C<$\>, C<@$>, C<@\>, or a C<$> or C<@> followed by white space;
one with an odd run of backslashes just before the C<\n>; one with a C<$>
and one other non-word character other than C<$> or C<@> just before it
(C<"a$^\n"> is C<$^\> and C<n>); and one with a C<$> or C<@> just before
it, except C<$$> or C<$@> after a character other than C<$>, C<@> or
C<\>. So C<"pid $$\n"> and C<"$@\n"> are reported, but C<"a\$\n">,
C<"a@\n">, C<"a$:\n"> and C<"$$$\n"> are not, though some of them do end
in a newline.

=item *

A C<qq> whose delimiter is a word character, as in C<qq n a\nn>, is not
reported.

=item *

C<use if COND, feature =E<gt> 'say'> is not recognised, so code that
enables C<say> that way is not checked.

=item *

C<say> sets C<local $\ = "\n">, so if the program sets C<$\> the output
changes: C<print "x\n"> prints C<"x\n"> followed by C<$\>, while C<say "x">
prints C<"x\n">. The violation is still reported, but with no fix, when the
file's text contains C<$\>, C<$OUTPUT_RECORD_SEPARATOR>, C<$ORS> or
C<output_record_separator> anywhere, even in a string, regex, heredoc or
comment (but not C<$$\>, as in C<"pid $$\n">); mentions the globs C<*\>,
C<*ORS> and C<*OUTPUT_RECORD_SEPARATOR>, or C<$ \> with a space; has a
C<#!> line with an C<-l> switch; or has a symbolic C<${...}> or C<*{...}>
that is not one of two shapes taken to be safe:

=over 4

=item *

a scalar variable, with optional subscripts that have no backslash or ORS
name in them: C<${$ref}>, C<${ $self-E<gt>{x} }>, but only when strict refs
appears to be in effect, so the variable should hold a reference. That means a
top-level C<use strict> (bare or naming C<refs>) or C<use v5.12> or later
comes first, and the file has no C<no strict> and no C<use VERSION> below
5.12. Otherwise C<${$name}> and C<$$name> may name C<$\>, and have no fix;

=item *

strings and scalar variables joined with C<.>, with no backslash, whose
text ends in a literal C<::name> other than C<ORS> or
C<OUTPUT_RECORD_SEPARATOR>: C<*{"${class}::foo"}>. Literal parts are
joined first, so C<"main::O" . "RS"> names C<ORS>.

=back

Anything else, such as C<${"\\"}>, C<${ chr(92) }>, a C<qw> or heredoc,
or C<${ "main::" . $name }>, has no fix.

Not seen: a C<$\> set in another file or module; stash access
(C<$main::{ORS}>, C<$::{"\\"}>) and glob slots (C<*{$glob}{SCALAR}>, with a
glob from C<Symbol::qualify_to_ref>); method names built at run time
(C<< STDOUT->can("output_" . "record_separator") >>, C<< STDOUT->$m(...) >>);
strict refs turned off without a C<no strict> statement
(C<BEGIN { strict-E<gt>unimport('refs') }>, C<$^H>, a module's C<import>);
and a C<$\> set in a string C<eval>.

=item *

C<say> passes its newline through C<$\>, so a tied handle whose C<PRINT>
ignores C<$\> loses the newline. This is a known caveat of the fix being
labelled safe.

=back

Not selected by default; select it with C<U> or C<U002>.

=cut
