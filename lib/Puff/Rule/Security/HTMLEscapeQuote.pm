package Puff::Rule::Security::HTMLEscapeQuote;

use v5.36;
use parent 'Puff::Rule';

sub code       {'S017'}
sub summary    {q{Escape ' in a hand-written HTML escaper}}
sub applies_to {'PPI::Token::Regexp::Substitute'}
sub fix_safety {'unsafe'}
sub cwe        {79}

sub explanation {
    return <<~'END';
        A hand-written HTML escaper that turns `<` and `"` into entities but
        leaves `'` alone is not safe for single-quoted attributes:
        `<a title='$escaped'>` lets a value close the attribute with `'` and
        add its own, such as `' onmouseover='alert(1)` (CWE-79, cross-site
        scripting).

        The rule looks at the substitutions in each sub, or at the top level
        of the file, and reports when they escape both `<` and `"` but none
        of them matches `'`. That covers one substitution per character
        (`s/"/&quot;/g`) and one substitution over a character class
        (`s/([<>&"])/$ESCAPE{$1}/g`).

        The unsafe fix adds `s/'/&#39;/g` after the `"` substitution,
        written the same way (same target, delimiters and modifiers). It
        runs after the `&` substitution as long as `"` does, so the `&` it
        adds is not escaped twice. It is unsafe because it changes the
        escaper's output, which tests that compare it will notice. A
        character-class substitution is not fixed, since its replacement
        usually needs a new entry in a lookup table. A module escaper such
        as HTML::Entities' `encode_entities` or HTML::Escape's
        `escape_html` escapes `'` already.
        END
}

my $LT    = qr/\A \\? < \z/x;
my $QUOTE = qr/\A \\? " \z/x;
my $APOS  = qr/ ' | \\x\{?27\}? | \\0?47 | \\N\{U\+0?0?27\} /xi;

my $LT_ENTITY    = qr/\A & (?: lt | \#0*60 | \#x0*3c ) ; \z/xi;
my $QUOTE_ENTITY = qr/\A & (?: quot | \#0*34 | \#x0*22 ) ; \z/xi;

sub check ( $self, $elem, $doc ) {
    my $kind = _kind($elem) or return;
    return if $kind eq 'lt';
    my @peers = _peers($elem);
    return if grep { _matches_apos($_) } @peers;
    if ( $kind eq 'quote' ) {
        return unless grep { ( _kind($_) // q{} ) eq 'lt' } @peers;
        return $self->violation( $elem, message => q{HTML escaper escapes " but not '; add s/'/&#39;/g} );
    }
    return $self->violation(
        $elem,
        message => q{HTML escaper escapes " but not '; add ' to the character class and its entity},
        fixable => 0,
    );
}

sub fix ( $self, $violation, $fix ) {
    my $elem = $violation->element;
    return 0 unless ( _kind($elem) // q{} ) eq 'quote';
    my $sections = $elem->{sections};
    return 0 unless @$sections == 2;

    # Rebuild the token with ' as the pattern and &#39; as the replacement,
    # replacing the later section first so the earlier offsets hold.
    my $text = $elem->content;
    return 0 if $text =~ /\As\s*'/;
    substr( $text, $sections->[1]{position}, $sections->[1]{size}, '&#39;' );
    substr( $text, $sections->[0]{position}, $sections->[0]{size}, q{'} );

    my %modifiers = $elem->get_modifiers;
    if ( $modifiers{r} ) {

        # s///r returns the result, so chain the new substitution onto it.
        $fix->insert_after( $elem, " =~ $text" );
        return 1;
    }

    my $stmt = $elem->statement or return 0;
    return 0 unless ref $stmt eq 'PPI::Statement' && _is_simple_substitution( $stmt, $elem );
    my $source = $fix->source->text;
    my $start  = $fix->source->start_of($stmt);
    my $line   = rindex( $source, "\n", $start - 1 ) + 1;
    my $indent = substr( $source, $line, $start - $line );
    return 0 if $indent =~ /\S/;

    my $new = $stmt->content;
    my $at  = $fix->source->start_of($elem) - $start;
    substr( $new, $at, length $elem->content, $text );
    $fix->insert_after( _line_end($stmt), "\n$indent$new" );
    return 1;
}

# The last token on the line $stmt ends on: its trailing comment, if any.
sub _line_end ($stmt) {
    my $token = $stmt->last_token;
    my $next  = $token->next_token;
    $next = $next->next_token while $next && $next->isa('PPI::Token::Whitespace') && $next->content !~ /\n/;
    return $next && $next->isa('PPI::Token::Comment') ? $next : $token;
}

# A statement that is only `TARGET =~ s///;` or `s///;`, so a copy of it
# with a different substitution does the same thing to the same target.
sub _is_simple_substitution ( $stmt, $elem ) {
    my @tokens = $stmt->schildren;
    pop @tokens if @tokens && $tokens[-1]->isa('PPI::Token::Structure') && $tokens[-1]->content eq ';';
    return 0 unless @tokens && $tokens[-1] == $elem;
    return 1 if @tokens == 1;
    return 0 unless @tokens >= 3 && $tokens[-2]->isa('PPI::Token::Operator') && $tokens[-2]->content eq '=~';
    for my $token ( @tokens[ 0 .. $#tokens - 2 ] ) {
        return 0
            unless $token->isa('PPI::Token::Symbol')
            || $token->isa('PPI::Token::Cast')
            || $token->isa('PPI::Structure::Subscript')
            || $token->isa('PPI::Token::Operator') && $token->content eq '->';
    }
    return 1;
}

# 'lt' or 'quote' for a substitution of that one character with its
# entity; 'class' for a substitution over a character class or
# alternation that holds both < and " but not '.
sub _kind ($elem) {
    my $sections = $elem->{sections};
    return unless $sections && @$sections == 2;
    my $pattern     = $elem->get_match_string      // return;
    my $replacement = $elem->get_substitute_string // return;
    return 'lt' if $pattern    =~ $LT    && $replacement =~ $LT_ENTITY;
    return 'quote' if $pattern =~ $QUOTE && $replacement =~ $QUOTE_ENTITY;
    return 'class'
        if $pattern     =~ /\A \(? (?: \[ [^\]]* \] | [^()]* \| [^()]* ) \)? \z/x
        && $pattern     =~ /</
        && $pattern     =~ /"/
        && $pattern     !~ $APOS
        && $replacement =~ / & | \$ \w+ (?: -> )? \{ | \bord\b /x;
    return;
}

sub _matches_apos ($elem) {
    my $pattern = $elem->get_match_string // return 0;
    return $pattern =~ $APOS ? 1 : 0;
}

# The substitutions in the same sub as $elem, or at the top level of the
# file when it is in no sub.
sub _peers ($elem) {
    my $scope = $elem;
    while ( $scope = $scope->parent ) {
        last if $scope->isa('PPI::Statement::Sub') || $scope->isa('PPI::Document');
        last
            if $scope->isa('PPI::Structure::Block')
            && $scope->sprevious_sibling
            && $scope->sprevious_sibling->isa('PPI::Token::Word')
            && $scope->sprevious_sibling->content eq 'sub';
    }
    return unless $scope;
    my $in_sub = !$scope->isa('PPI::Document');
    my $found  = $scope->find('PPI::Token::Regexp::Substitute') || [];
    return @$found if $in_sub;
    return grep { !_in_sub($_) } @$found;
}

sub _in_sub ($elem) {
    while ( $elem = $elem->parent ) {
        return 1 if $elem->isa('PPI::Statement::Sub');
        return 1
            if $elem->isa('PPI::Structure::Block')
            && $elem->sprevious_sibling
            && $elem->sprevious_sibling->isa('PPI::Token::Word')
            && $elem->sprevious_sibling->content eq 'sub';
    }
    return 0;
}

1;

# ABSTRACT: S017 - escape ' in a hand-written HTML escaper

__END__

=pod

=head1 DESCRIPTION

Reports a hand-written HTML escaper whose substitutions escape C<< < >> and
C<"> but not C<'>. The unsafe fix adds C<s/'/&#39;/g> after the C<"> rule.

=cut
