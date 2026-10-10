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
        `$fh->print(...)` and `print =>`. Nor is a string whose `\n`
        follows an unescaped `$` or `@`: in `"a$\n"` the `$\` is the
        variable, so the string does not end in a newline (`"a\$\n"` does,
        and is reported). A `qq` whose delimiter is a letter, digit or `_`
        (`qq n a\nn`) is skipped. `use if ..., feature => 'say'` is not
        recognised, so code that enables `say` that way is not checked.

        The fix replaces `print` with `say` and removes the trailing `\n`
        from the string, keeping its quotes. It is safe, except that `say`
        always ends the output with "\n" where `print` adds `$\`. So the
        violation has no fix when the file mentions `$\`,
        `$OUTPUT_RECORD_SEPARATOR` or `$ORS` (or the globs `*\`, `*ORS` and
        `*OUTPUT_RECORD_SEPARATOR`), uses a symbolic `${"..."}` or
        `*{"..."}` whose name has a backslash, names ORS or interpolates,
        calls `output_record_separator`, or has a `#!` line with an `-l`
        switch. A `$\` set in another file or module is not seen.

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
    return if $string     =~ /\\[Qc]/;
    return unless $string =~ /(?:\A|[^\\])(?:\\\\)*\\n\z/;

    # In `"a$\n"` the `$\` is a variable, not a `$` and a newline.
    return if $string =~ /(?:\A|[^\\])(?:\\\\)*[\$\@]\\n\z/;
    return if $string eq q{\n} && @$args > 1;    # `print $x, "\n"`
    return unless $quote->content =~ /\\n.\z/s;
    return $quote;
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
# end their output differently.
sub _sets_ors ($doc) {
    my $first = $doc->first_token;
    return 1 if $first && $first->isa('PPI::Token::Comment') && $first->content =~ /\A#!.*\s-\S*l/;
    return 1 if $doc->find_first(
        sub {
            my $elem = $_[1];
            return 1 if $elem->isa('PPI::Token::Magic') && $elem->content eq '$\\';
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

            # A symbolic `${"\\"}` or `*{"main::ORS"}`, or one whose name is
            # not a literal.
            if ( $elem->isa('PPI::Token::Cast') && $elem->content =~ /\A[\$*]\z/ ) {
                my $block = $elem->snext_sibling;
                return 1 if $block && $block->isa('PPI::Structure::Block') && _names_ors($block);
            }
            return 1 if $elem->isa('PPI::Token::Word') && $elem->content =~ /(?:\A|::|->)output_record_separator\z/;
            return 0;
        }
    );
    return 0;
}

# Whether a deref block's name may be the output record separator: it
# holds a string with a backslash or naming ORS, or an interpolating
# string with a variable in it.
sub _names_ors ($block) {
    for my $quote ( @{ $block->find('PPI::Token::Quote') || [] } ) {
        my $string = $quote->string;
        return 1 if $string =~ /\\|ORS|OUTPUT_RECORD_SEPARATOR/;
        return 1
            if !$quote->isa('PPI::Token::Quote::Single')
            && !$quote->isa('PPI::Token::Quote::Literal')
            && $string =~ /[\$\@]/;
    }
    return 0;
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

A string whose final C<\n> follows an unescaped C<$> or C<@> is not
reported. In C<"a$\n"> the C<$\> is a variable followed by an C<n>, not a
C<$> and a newline, and dropping the C<\n> would not compile. C<"a\$\n">
has an escaped dollar and is reported.

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
file mentions C<$\>, C<$OUTPUT_RECORD_SEPARATOR> or C<$ORS> (or the globs
C<*\>, C<*ORS> and C<*OUTPUT_RECORD_SEPARATOR>), uses a symbolic
C<${"..."}> or C<*{"..."}> whose name has a backslash, names ORS or
interpolates, calls C<output_record_separator>, or has a C<#!> line with an
C<-l> switch. A C<$\> set in another file or module is not seen.

=item *

C<say> passes its newline through C<$\>, so a tied handle whose C<PRINT>
ignores C<$\> loses the newline. This is a known caveat of the fix being
labelled safe.

=back

Not selected by default; select it with C<U> or C<U002>.

=cut
