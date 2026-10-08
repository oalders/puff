package Puff::Rule::Security::ExtensionRegex;

use v5.36;
use parent 'Puff::Rule';

sub code       {'S014'}
sub summary    {'Anchor a file extension check with \z'}
sub applies_to { [ 'PPI::Token::Regexp::Match', 'PPI::Token::QuoteLike::Regexp' ] }
sub fix_safety {'unsafe'}
sub cwe        {184}

sub explanation {
    return <<~'END';
        A file extension check that is not anchored at the very end of the
        name lets other names through. `/\.(pl|cgi)/` accepts
        `evil.pl.txt`, and `qr/\Q$ext\E/` accepts `file.pdf.exe` when
        `$ext` is `pdf`. `$` and `\Z` also match before a trailing newline,
        so `/\.jpg$/` accepts `"x.jpg\n"`, a different file name (CWE-184,
        incomplete list of disallowed inputs).

        The rule reports a match or qr// whose whole pattern is a file
        extension: `\.` followed by a word or a group of words
        (`\.(?:pl|cgi)`), or `\Q$ext\E` where the variable's name contains
        `ext` or `suffix`, either with no end anchor or ending in `$` or
        `\Z` (without /m). A suffix pattern passed to `basename` or
        `fileparse`, which anchor it themselves, is not reported.

        The unsafe fix anchors the pattern with `\z`: `$` and `\Z` become
        `\z`, and a pattern with no anchor gets one. It is unsafe because a
        check that meant "contains .pm" stops matching names like `x.pm.bak`.
        END
}

my $WORDS     = qr/[^\W_][\w?]* (?: \\\. [\w?]+ )*/x;
my $EXTENSION = qr/
    \\\. (?: $WORDS | \( (?:\?:)? $WORDS (?: \| $WORDS )* \) )
  | (?: \\\. )? \\Q \$ \w*? (?i: ext | suffix ) \w* \\E
/x;

sub check ( $self, $elem, $doc ) {
    my ( $anchor, undef ) = _finding($elem) or return;
    my $message
        = $anchor eq q{}
        ? 'File extension check is not anchored, so other names pass it; end the pattern with \z'
        : "$anchor also matches before a trailing newline; end the pattern with \\z";
    return $self->violation( $elem, message => $message );
}

sub fix ( $self, $violation, $fix ) {
    my $elem = $violation->element;
    my ( $anchor, $pattern ) = _finding($elem) or return 0;
    my $section = $elem->{sections}[0];
    my $start   = $fix->source->start_of($elem) + $section->{position};
    $fix->replace_range( $start, $start + $section->{size}, substr( $pattern, 0, length($pattern) - length($anchor) ) . '\z' );
    return 1;
}

# ( end anchor, pattern ) for an extension check that is not anchored with
# \z; the anchor is '$', '\Z' or ''.
sub _finding ($elem) {
    my $sections = $elem->{sections};
    return unless $sections && @$sections == 1;
    my $pattern = $elem->get_match_string // return;
    my %modifiers = $elem->get_modifiers;
    return if $modifiers{x} || $modifiers{m} && $pattern =~ /\$\z/;
    return unless $pattern =~ /\A $EXTENSION ( \$ | \\Z )? \z/x;
    return if _is_suffix_argument($elem);
    return ( $1 // q{}, $pattern );
}

my %SUFFIX_TAKER = map { $_ => 1 } qw( basename fileparse );

# Whether $elem is an argument of basename or fileparse.
sub _is_suffix_argument ($elem) {
    my $list = $elem->parent && $elem->parent->parent;
    return 0 unless $list && $list->isa('PPI::Structure::List');
    my $word = $list->sprevious_sibling;
    return $word && $word->isa('PPI::Token::Word') && $SUFFIX_TAKER{ $word->content =~ s/.*:://r } ? 1 : 0;
}

1;

# ABSTRACT: S014 - anchor a file extension check with \z

__END__

=pod

=head1 DESCRIPTION

Reports a regex whose whole pattern is a file extension (C<\.(pl|cgi)>,
C<\Q$ext\E>) that is not anchored at the very end with C<\z>. The unsafe
fix anchors it.

=cut
