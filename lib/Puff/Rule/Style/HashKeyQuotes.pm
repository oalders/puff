package Puff::Rule::Style::HashKeyQuotes;

use v5.36;
use parent 'Puff::Rule';

use PPI           ();
use Puff::PPIUtil qw( is_sole_subscript_key );

sub code       {'Q002'}
sub summary    {'Hash key does not need quotes'}
sub applies_to {'PPI::Token::Quote'}
sub fix_safety {'safe'}

sub explanation {
    return <<~'END';
        Perl quotes a bareword hash key for you: `$h{name}` means
        `$h{'name'}`, and `name => 1` means `'name' => 1`. Quotes around
        such a key are noise.

        The rule reports a quoted string that is the only thing in a hash
        subscript (`$h{'name'}`, `$h->{"name"}`, `@h{'name'}`) or that sits
        just left of a fat comma (`'name' => 1`), when its text is a plain
        ASCII identifier: a letter or underscore followed by letters, digits
        and underscores. The fix removes the quotes and is safe: the key is
        the same string.

        These keys are left alone: numbers (`'01'` and `01` differ), names
        with `::` or `-`, the quote-like operators `q`, `qq`, `qw`, `qx`, `m`,
        `s`, `tr` and `y`, the operator `x`, v-strings such as `v2`, and names
        like `__PACKAGE__`, which read as something other than a string.
        Slices with more than one key (`@h{'a', 'b'}`) need their quotes and
        are not reported.

        This rule is not selected by default. Turn it on with `--select Q` or
        `extend-select = ["Q"]`.
        END
}

my %SPECIAL = map { $_ => 1 } qw( q qq qw qx m s tr y x );

sub check ( $self, $elem, $doc ) {
    return unless defined _bare_key($elem);
    return $self->violation( $elem, message => 'Hash key does not need quotes' );
}

sub fix ( $self, $violation, $fix ) {
    my $key = _bare_key( $violation->element ) // return 0;
    $fix->replace( $violation->element, $key );
    return 1;
}

# The key as a bareword if $elem is a quoted hash key that needs no quotes,
# else undef.
sub _bare_key ($elem) {
    return
           unless $elem->isa('PPI::Token::Quote::Single')
        || $elem->isa('PPI::Token::Quote::Double')
        || $elem->isa('PPI::Token::Quote::Literal')
        || $elem->isa('PPI::Token::Quote::Interpolate');
    my $key = $elem->string;
    return unless $key =~ /\A[A-Za-z_][A-Za-z0-9_]*\z/;
    return if $SPECIAL{$key} || $key =~ /\A__.*__\z/;
    my $context = is_sole_subscript_key($elem) ? 'subscript' : _is_fat_comma_key($elem) ? 'fat-comma' : return;
    return unless _ppi_sees_word( $key, $context );
    return $key;
}

# 'key' => ...: the next significant token is a fat comma.
sub _is_fat_comma_key ($elem) {
    my $next = $elem->snext_sibling or return 0;
    return $next->isa('PPI::Token::Operator') && $next->content eq '=>';
}

# Make sure PPI parses the unquoted key as a plain word in the same place,
# so the fixed text means the same to every later rule.
my %PPI_SEES_WORD;

sub _ppi_sees_word ( $key, $context ) {
    return $PPI_SEES_WORD{"$context $key"} //= do {
        my $code = $context eq 'subscript' ? "\$h{$key};" : "f($key => 1);";
        my $ppi  = PPI::Document->new( \$code );
        my $word = $ppi && $ppi->find_first( sub { $_[1]->isa('PPI::Token') && $_[1]->content eq $key } );
        $word && ref $word eq 'PPI::Token::Word' ? 1 : 0;
    };
}

1;

# ABSTRACT: Q002 - hash key does not need quotes

__END__

=pod

=head1 DESCRIPTION

Reports a quoted hash key that Perl would quote by itself: the only thing in
a C<{...}> subscript, or the string just left of C<< => >>, when its text is
a plain ASCII identifier. The fix removes the quotes and is safe.

Not selected by default; select it with C<Q> or C<Q002>.

=cut
