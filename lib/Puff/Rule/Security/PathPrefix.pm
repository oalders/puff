package Puff::Rule::Security::PathPrefix;

use v5.36;
use parent 'Puff::Rule';

use Puff::PPIUtil qw( is_builtin_call call_args );

sub code       {'S015'}
sub summary    {'Directory containment checked with a bare prefix test'}
sub applies_to { [ 'PPI::Token::Word', 'PPI::Token::Regexp::Match' ] }
sub fix_safety {'unsafe'}
sub cwe        {22}

sub explanation {
    return <<~'END';
        Checking that a path is inside a directory by testing for a string
        prefix lets sibling directories through: `/srv/www-private` starts
        with `/srv/www`. When the check guards file access, that is a path
        traversal (CWE-22).

        The rule reports, when the prefix is a variable whose name looks
        like a directory (it contains root, dir, base, home, top, parent,
        folder or path):

        - `index($path, $root) == 0`, `0 == index(...)`, `!index(...)` and
          `index(...) != 0`;
        - `substr($path, 0, length $root) eq $root`;
        - `$path =~ /^\Q$root\E/` with nothing after the `\E`.

        Match a whole directory instead:
        `$path =~ m{\A\Q$root\E(?:/|\z|(?<=/))}`. The last alternative
        accepts a root that already ends in `/`. Resolve both paths (with
        `realpath` or `Cwd::abs_path`) before comparing them, too.

        The unsafe fix rewrites the `index` and regex forms that way. It is
        unsafe because paths in sibling directories stop matching, which is
        the point, but may be something the code relied on. The substr form
        is not fixed.
        END
}

my $DIRECTORY = qr/root|dir|base|home|top|parent|folder|path/i;
my $BOUNDARY  = '(?:/|\z|(?<=/))';
my $MESSAGE
    = 'Prefix test lets sibling paths (/srv/www-private for /srv/www) pass; match m{\A\Q$root\E(?:/|\z)} instead';

sub check ( $self, $elem, $doc ) {
    if ( $elem->isa('PPI::Token::Regexp::Match') ) {
        return unless _anchored_prefix($elem);
        return $self->violation( $elem, message => $MESSAGE, fixable => defined _boundary($elem) ? 1 : 0 );
    }
    my $content = $elem->content;
    if ( $content eq 'index' ) {
        my $test = _index_test($elem) or return;
        return $self->violation( $elem, message => $MESSAGE, fixable => $test->{fix} ? 1 : 0 );
    }
    if ( $content eq 'substr' && _substr_test($elem) ) {
        return $self->violation( $elem, message => $MESSAGE, fixable => 0 );
    }
    return;
}

sub fix ( $self, $violation, $fix ) {
    my $elem   = $violation->element;
    my $source = $fix->source;
    if ( $elem->isa('PPI::Token::Regexp::Match') ) {
        my $prefix   = _anchored_prefix($elem) or return 0;
        my $boundary = _boundary($elem) // return 0;
        my $section  = $elem->{sections}[0];
        my $start    = $source->start_of($elem) + $section->{position};
        $fix->replace_range( $start, $start + $section->{size}, $prefix . $boundary );
        return 1;
    }
    my $test  = _index_test($elem) or return 0;
    my $fixed = $test->{fix}       or return 0;
    my $op    = $test->{negated} ? '!~' : '=~';
    $fix->replace_range(
        $source->start_of( $test->{first} ),
        $source->end_of( $test->{last} ),
        "$fixed->[0] $op m{\\A\\Q$fixed->[1]\\E$BOUNDARY}",
    );
    return 1;
}

# The pattern text of a match that is only ^\Q$dir\E or \A\Q$dir\E, or undef.
sub _anchored_prefix ($elem) {
    my $sections = $elem->{sections};
    return unless $sections && @$sections == 1;
    my $pattern = $elem->get_match_string // return;
    return unless $pattern =~ /\A (?: \^ | \\A ) \\Q (\$ [^\\]+) \\E \z/x;
    return unless _is_directory_name($1);
    return $pattern;
}

# The boundary text to append inside $elem's delimiters, or undef when they
# would clash with it.
sub _boundary ($elem) {
    my $type = $elem->{sections}[0]{type};
    return $BOUNDARY =~ s{/}{\\/}gr if $type eq '//';
    return $BOUNDARY if $type eq '{}' || $type eq '[]' || $type eq '!!' || $type eq '##';
    return;
}

# For index(HAYSTACK, NEEDLE) compared with 0: { first, last, negated, fix }
# where first..last is the whole test and fix is [ haystack, needle ] text
# when both are plain enough to move into a regex.
sub _index_test ($word) {
    return unless is_builtin_call($word);
    my $list = $word->snext_sibling;
    return unless $list && $list->isa('PPI::Structure::List');
    my $args = call_args($word);
    return unless @$args == 2;
    my ( $haystack, $needle ) = @$args;
    return unless _is_directory_name( join q{}, map { $_->content } @$needle );

    my ( $first, $last, $negated );
    my $next = $list->snext_sibling;
    my $prev = $word->sprevious_sibling;
    if ( _is_op( $next, '==', '!=' ) && _is_zero( $next->snext_sibling ) ) {
        ( $first, $last, $negated ) = ( $word, $next->snext_sibling, $next->content eq '!=' );
    }
    elsif ( _is_op( $prev, '==', '!=' ) && _is_zero( $prev->sprevious_sibling ) ) {
        ( $first, $last, $negated ) = ( $prev->sprevious_sibling, $list, $prev->content eq '!=' );
    }
    elsif ( _is_op( $prev, '!' ) ) {
        ( $first, $last, $negated ) = ( $prev, $list, 0 );
    }
    else {
        return;
    }

    my $fix;
    if ( _is_plain($haystack) && _is_plain($needle) ) {
        $fix = [
            map {
                join q{},
                    map { $_->content } @$_
            } $haystack,
            $needle
        ];
    }
    return { first => $first, last => $last, negated => $negated, fix => $fix };
}

# substr(PATH, 0, length DIR) eq DIR, or DIR eq substr(...).
sub _substr_test ($word) {
    return 0 unless is_builtin_call($word);
    my $args = call_args($word);
    return 0 unless @$args == 3 && @{ $args->[1] } == 1 && _is_zero( $args->[1][0] );
    my @length = @{ $args->[2] };
    return 0 unless @length && $length[0]->isa('PPI::Token::Word') && $length[0]->content eq 'length';
    shift @length;
    @length = map { $_->isa('PPI::Structure::List') ? $_->schildren : $_ } @length;
    return 0 unless _is_directory_name( join q{}, map { $_->content } @length );
    my $list = $word->snext_sibling;
    my $next = $list && $list->isa('PPI::Structure::List') ? $list->snext_sibling : undef;
    my $prev = $word->sprevious_sibling;
    return _is_op( $next, 'eq', 'ne' ) || _is_op( $prev, 'eq', 'ne' ) ? 1 : 0;
}

sub _is_directory_name ($text) {
    my ($name) = $text =~ /\A[\$\@%]?\{?\$?(\w+)/ or return 0;
    my @keys = $text =~ /(?: \{ \s* ['"]? | -> ) (\w+)/xg;
    return grep {/$DIRECTORY/} $name, @keys;
}

# A scalar, optionally with ->[...] / ->{...} subscripts: text that
# interpolates the same way in a regex.
sub _is_plain ($elements) {
    my ( $symbol, @rest ) = @$elements;
    return 0 unless $symbol && $symbol->isa('PPI::Token::Symbol') && $symbol->raw_type eq '$';
    for my $el (@rest) {
        next if $el->isa('PPI::Structure::Subscript');
        next if _is_op( $el, '->' );
        return 0;
    }
    return 1;
}

sub _is_op ( $elem, @ops ) {
    return 0 unless $elem && $elem->isa('PPI::Token::Operator');
    my $content = $elem->content;
    return grep { $_ eq $content } @ops;
}

sub _is_zero ($elem) {
    return $elem && $elem->isa('PPI::Token::Number') && $elem->content eq '0';
}

1;

# ABSTRACT: S015 - directory containment checked with a bare prefix test

__END__

=pod

=head1 DESCRIPTION

Reports a prefix test (C<index(...) == 0>, C<substr ... eq>, C</^\Q$root\E/>)
used to check that a path is inside a directory, which lets sibling
directories pass. The unsafe fix matches a whole directory instead.

=cut
