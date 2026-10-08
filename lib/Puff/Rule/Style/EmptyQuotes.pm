package Puff::Rule::Style::EmptyQuotes;

use v5.36;
use parent 'Puff::Rule';

sub code       {'Q003'}
sub summary    {'Use q{} for an empty string'}
sub applies_to { [ 'PPI::Token::Quote::Single', 'PPI::Token::Quote::Double' ] }
sub fix_safety {'safe'}

sub explanation {
    return <<~'END';
        `''` and `""` are easy to misread: in many fonts `''` looks like `"`,
        and `" "` (a space) looks like `""`. `q{}` cannot be mistaken for
        anything else.

        The rule reports `''` and `""`, and the fix rewrites them as `q{}`.
        The value is the same empty string, so the fix is safe. `q()`,
        `qq{}` and other quote-like forms are left alone.

        This rule is not selected by default. Turn it on with `--select Q` or
        `extend-select = ["Q"]`.
        END
}

sub check ( $self, $elem, $doc ) {
    return unless _is_empty($elem);
    return $self->violation( $elem, message => 'Use q{} for an empty string' );
}

sub fix ( $self, $violation, $fix ) {
    return 0 unless _is_empty( $violation->element );
    $fix->replace( $violation->element, 'q{}' );
    return 1;
}

sub _is_empty ($elem) {
    my $content = $elem->content;
    return $content eq q{''} || $content eq q{""};
}

1;

# ABSTRACT: Q003 - use q{} for an empty string

__END__

=pod

=head1 DESCRIPTION

Reports C<''> and C<""> and fixes them by writing C<q{}>. The fix is safe:
the value is the same empty string.

Not selected by default; select it with C<Q> or C<Q003>.

=cut
