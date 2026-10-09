package Puff::Rule::Bugs::FormatArgCount;

use v5.36;
use parent 'Puff::Rule';

use Puff::PPIUtil qw( is_builtin_call call_args is_constant_string );

my %FUNCTION = map { $_ => 1 } qw( sprintf printf CORE::sprintf CORE::printf );

# Operators whose operands and result are single scalars. `..`, `=`, `,`,
# `or` and the like are missing on purpose: an argument using them is skipped.
my %SCALAR_OP = map { $_ => 1 } qw( . + - * / % ** x == != < > <= >= <=> eq ne lt gt le ge cmp && || // ! ? : );

# One conversion after its `%`: an optional explicit index, flags, a vector
# flag, width, precision, size and the conversion letter (perldoc -f sprintf).
my $CONVERSION = qr{
    \G
    (?<index> [0-9]+ \$ )?
    [-+ 0\#]*
    (?<vector> \* (?: [0-9]+ \$ )? v | v )?
    (?<width> [0-9]+ | \* (?: [0-9]+ \$ )? )?
    (?: \. (?<precision> [0-9]* | \* (?: [0-9]+ \$ )? ) )?
    (?: hh | h | ll | l | q | L | V | z | t | j )?
    [csduoxXeEfFgGbBpaAiDUO]
}x;

sub code            {'B009'}
sub summary         {'sprintf/printf argument count does not match the format'}
sub applies_to      {'PPI::Token::Word'}
sub explicit_select {1}

sub explanation {
    return <<~'END';
        A sprintf or printf format with more conversions than arguments
        fills the missing ones with an empty string or 0, and one with fewer
        conversions ignores the extra arguments. Perl only warns ("Missing
        argument in sprintf", "Redundant argument in sprintf") at runtime:

            sprintf '%s: %d', $name;    # the %d gets nothing
            printf "%s\n", $a, $b;      # $b is never printed

        The rule checks a call only when its format is one literal string
        ('...', q{...}, or "..." / qq{...} with nothing interpolated and no
        escape such as \x25 that could hide a %) and every other argument
        is plainly one value: a scalar variable or element, a number, a
        string, `scalar(...)`, or such values joined by scalar operators.
        An array, hash, function or method call, list in parentheses,
        heredoc or concatenated format makes it skip the call, since the
        count is unknown. `%%` takes no argument, a `*` width or precision
        takes one more, and `%*vd` takes two. A format with an explicit
        index (`%1$s`) or an invalid conversion is skipped. The filehandle
        of `printf STDERR ...`, `printf {$fh} ...` and `printf $fh ...` is
        not counted. There is no fix.

        Not selected by default, not even by `--select B`: enable it by its
        exact code (`--extend-select B009`) or with `ALL`.
        END
}

sub check ( $self, $elem, $doc ) {
    my $name = $elem->content;
    return unless $FUNCTION{$name} && is_builtin_call($elem);

    my $args = call_args($elem);
    return unless @$args;

    my @first = @{ $args->[0] };
    shift @first if $name =~ /(?:\A|::)printf\z/ && _is_filehandle(@first);
    return unless @first == 1;
    my $format = _format_string( $first[0] ) // return;
    my $want   = _conversions($format)       // return;

    my @rest = @{$args}[ 1 .. $#$args ];
    return if grep { !_is_scalar_arg(@$_) } @rest;
    my $got = @rest;
    return if $got == $want;

    my $func = $name =~ s/\ACORE:://r;
    my $kind = $got < $want ? 'Missing' : 'Redundant';
    return $self->violation(
        $elem,
        message => "$kind argument in $func: format expects $want, got $got",
    );
}

# printf FH FORMAT, printf {$fh} FORMAT and printf $fh FORMAT: the
# filehandle and the format are one argument group, with no comma between.
sub _is_filehandle (@group) {
    return 0 unless @group == 2;
    my ($fh) = @group;
    return 1 if $fh->isa('PPI::Token::Word') && $fh->content =~ /\A[A-Za-z_]\w*(?:::\w+)*\z/;
    if ( $fh->isa('PPI::Structure::Block') ) {
        my @inner = $fh->schildren;
        return 0 unless @inner == 1;
        my @tokens = $inner[0]->schildren;
        return @tokens == 1 && $tokens[0]->isa('PPI::Token::Symbol') && $tokens[0]->content =~ /\A\$\w+\z/;
    }
    return 1
        if $fh->isa('PPI::Token::Symbol')
        && $fh->content =~ /\A\$\w+\z/
        && $fh->next_sibling
        && $fh->next_sibling->isa('PPI::Token::Whitespace');
    return 0;
}

# The text of a literal format, or undef when it is not one.
sub _format_string ($elem) {
    return undef unless $elem->isa('PPI::Token::Quote') && is_constant_string($elem);
    my $string = $elem->string;
    return $string unless $elem->isa('PPI::Token::Quote::Double') || $elem->isa('PPI::Token::Quote::Interpolate');

    # An escape such as \x25, \045, \N{...} or \L could produce or hide a %.
    while ( $string =~ /\\(.)/gs ) {
        my $escaped = $1;
        return undef if $escaped =~ /\w/ && $escaped !~ /[ntrfae]/;
    }
    return $string;
}

# The number of arguments a format takes, or undef when it cannot tell.
sub _conversions ($format) {
    my $count = 0;
    while ( $format =~ /%/g ) {
        my $at = pos $format;
        if ( substr( $format, $at, 1 ) eq '%' ) {
            pos($format) = $at + 1;
            next;
        }
        return undef unless $format =~ /$CONVERSION/gc;
        return undef if grep { defined && /\$/ } @+{qw( index vector width precision )};
        $count += 1 + grep { defined && /\A\*/ } @+{qw( vector width precision )};
    }
    return $count;
}

# True when the tokens of one argument can only give one value.
sub _is_scalar_arg (@tokens) {
    return 0 unless @tokens;
    my ( $questions, $colons ) = ( 0, 0 );
    my $prev;
    while ( defined( my $t = shift @tokens ) ) {
        if ( $t->isa('PPI::Token::Word') && $t->content eq 'scalar' && @tokens ) {
            my $operand = shift @tokens;
            return 0
                unless $operand->isa('PPI::Structure::List')
                || ( $operand->isa('PPI::Token::Symbol') && $operand->content =~ /\A[\$\@%]\w+\z/ );
        }
        elsif ( $t->isa('PPI::Structure::Subscript') ) {
            return 0
                unless $prev
                && ( $prev->isa('PPI::Token::Symbol')
                || $prev->isa('PPI::Structure::Subscript')
                || $prev->content eq '->' );
        }
        elsif ( $t->isa('PPI::Token::Operator') ) {
            my $op = $t->content;
            if ( $op eq '->' ) {
                return 0 unless @tokens && $tokens[0]->isa('PPI::Structure::Subscript');
            }
            else {
                return 0 unless $SCALAR_OP{$op};
                $questions++ if $op eq '?';
                $colons++ if $op eq ':';
            }
        }
        elsif ( $t->isa('PPI::Token::Symbol') ) {
            return 0 unless $t->content =~ /\A\$/;
        }
        elsif ( $t->isa('PPI::Token::Cast') ) {
            return 0 unless $t->content eq '$';
        }
        else {
            return 0
                unless $t->isa('PPI::Token::ArrayIndex')
                || $t->isa('PPI::Token::Number')
                || $t->isa('PPI::Token::Quote');
        }
        $prev = $t;
    }
    return $questions == $colons;
}

1;

# ABSTRACT: B009 - sprintf/printf argument count does not match the format

__END__

=pod

=head1 DESCRIPTION

Reports a C<sprintf> or C<printf> call whose literal format string takes a
different number of arguments than the call passes: Perl's runtime "Missing
argument in sprintf" and "Redundant argument in sprintf" warnings, found
before the code runs. There is no fix.

=head2 Rationale

A missing argument is formatted as an empty string or 0 and an extra one is
silently dropped, so the output is wrong without any error. Both usually
come from editing a format or its argument list and not the other.

=head2 Edge cases

The rule only reports what it can count for certain, and skips the call
otherwise:

=over 4

=item *

The format must be one literal string: a single-quoted string or C<q{}>, or
a double-quoted string or C<qq{}> with nothing interpolated and no escape
other than C<\n>, C<\t>, C<\r>, C<\f>, C<\a>, C<\e> or an escaped
punctuation character (C<\x25> is a C<%>). Variables, concatenations and
heredocs are skipped.

=item *

Each other argument must be one value: a scalar variable, element or
C<$#array>, a number, a string, C<scalar(...)> or C<scalar @array>, or those
combined with scalar operators such as C<.>, C<+> and C<?:>. An array, hash,
slice, function or method call, list in parentheses, C<qw()> or regex match
can expand to any number of values, and makes the rule skip the call.

=item *

C<%%> takes no argument. A C<*> width or precision (C<%*d>, C<%.*f>) takes
one more argument, and so does the C<*v> join string of a vector flag
(C<%*vd>). C<%vd> takes one.

=item *

A format with an explicit index (C<%2$s>, C<%*3$d>) or with a conversion
that is invalid or unusual (such as C<%n> or C<%y>) is skipped.

=item *

The filehandle of C<printf STDERR FORMAT, ...>, C<printf {$fh} FORMAT, ...>
and C<printf $fh FORMAT, ...> is not an argument. C<printf> with no
arguments prints C<$_> and is not checked. Method calls (C<< $obj->sprintf >>)
and hash keys (C<< sprintf => 1 >>) are not calls of the builtin.

=back

Not selected by default, and not by the prefix C<B> either: select it by
its exact code or with C<ALL>. See L<Puff::Rule/explicit_select>.

=cut
