package Puff::Rule::Style::SimpleStringQuotes;

use v5.36;
use parent 'Puff::Rule';

sub code       {'Q001'}
sub summary    {'Use single quotes for a string with nothing to interpolate'}
sub applies_to {'PPI::Token::Quote::Double'}
sub fix_safety {'safe'}

sub explanation {
    return <<~'END';
        A "..." string tells the reader to look for variables and escapes. When
        there are none, '...' says so up front.

        The rule reports a "..." string whose text has no backslash, `$`, `@`,
        `'` or `"`. For such a string, "..." and '...' produce the same value,
        so the fix rewrites `"coffee"` as `'coffee'` and is safe. qq{...},
        heredocs and strings that need any of those characters are left alone.

        This rule is not selected by default. Turn it on with `--select Q` or
        `extend-select = ["Q"]`.
        END
}

sub check ( $self, $elem, $doc ) {
    return unless defined _simple_value($elem);
    return $self->violation( $elem, message => 'Use single quotes for a string with nothing to interpolate' );
}

sub fix ( $self, $violation, $fix ) {
    my $value = _simple_value( $violation->element ) // return 0;
    $fix->replace( $violation->element, "'$value'" );
    return 1;
}

# The text between the quotes of a "..." string that means the same in '...',
# or undef. Same test as PPI::Token::Quote::Double::simplify.
sub _simple_value ($elem) {
    return unless ref $elem eq 'PPI::Token::Quote::Double';
    my $content = $elem->content;
    my $value   = substr $content, 1, -1;
    return if $value =~ /[\\\$\@'"]/;
    return $value;
}

1;

# ABSTRACT: Q001 - use single quotes for a string with nothing to interpolate

__END__

=pod

=head1 DESCRIPTION

Reports C<"..."> strings (L<PPI::Token::Quote::Double>, not C<qq>) whose text
has no backslash, C<$>, C<@>, C<'> or C<">, and fixes them by switching to
single quotes. The fix is safe: the string's value does not change.

Not selected by default; select it with C<Q> or C<Q001>.

=cut
