package Puff::PPIUtil;

use v5.36;

use Exporter qw( import );

our @EXPORT_OK = qw( is_builtin_call call_args is_constant_string is_sole_subscript_key command_body );

my $INTERPOLATES = qr/(?<!\\)(?:\\\\)*[\$\@]/;

my %STOP_WORD = map { $_ => 1 } qw( or and xor not if unless while until for foreach );

sub is_builtin_call ($word) {
    my $prev = $word->sprevious_sibling;
    return 0 if $prev && $prev->isa('PPI::Token::Operator') && $prev->content eq '->';

    my $next = $word->snext_sibling;
    return 0 if $next && $next->isa('PPI::Token::Operator') && $next->content eq '=>';

    my $parent = $word->parent or return 1;
    return 0 if $parent->isa('PPI::Statement::Sub');
    return 0 if $parent->isa('PPI::Statement::Package') || $parent->isa('PPI::Statement::Include');

    if (   $parent->isa('PPI::Statement::Expression')
        && $parent->parent
        && $parent->parent->isa('PPI::Structure::Subscript')
        && $parent->schildren == 1 ) {
        return 0;
    }
    return 1;
}

sub call_args ($word) {
    my $next = $word->snext_sibling;
    my @elements;
    if ( $next && $next->isa('PPI::Structure::List') ) {
        @elements = map { $_->schildren } grep { $_->isa('PPI::Statement::Expression') } $next->schildren;
    }
    else {
        my $el = $next;
        while ($el) {
            last if $el->isa('PPI::Token::Structure') && $el->content eq ';';
            last
                if ( $el->isa('PPI::Token::Word') || $el->isa('PPI::Token::Operator') )
                && $STOP_WORD{ $el->content };
            push @elements, $el;
            $el = $el->snext_sibling;
        }
    }

    return [] unless @elements;

    my @args = ( [] );
    for my $el (@elements) {
        if ( $el->isa('PPI::Token::Operator') && ( $el->content eq ',' || $el->content eq '=>' ) ) {
            push @args, [];
            next;
        }
        push @{ $args[-1] }, $el;
    }
    pop @args unless @{ $args[-1] };    # trailing comma
    return \@args;
}

sub is_constant_string ($elem) {
    return 1 if $elem->isa('PPI::Token::Quote::Single') || $elem->isa('PPI::Token::Quote::Literal');
    if ( $elem->isa('PPI::Token::Quote::Double') || $elem->isa('PPI::Token::Quote::Interpolate') ) {
        return $elem->string !~ $INTERPOLATES;
    }
    if ( $elem->isa('PPI::Token::HereDoc') ) {
        return 1 if ( $elem->{_mode} // '' ) eq 'literal';
        return join( q{}, $elem->heredoc ) !~ $INTERPOLATES;
    }
    return 0;
}

sub command_body ($elem) {
    my ( $delim, $body ) = $elem->content =~ /\A(?:qx\s*(.)|`)(.*)\z/s;
    return unless defined $body;
    $body =~ s/.\z//s;    # closing delimiter
    my $interpolates = !( defined $delim && $delim eq q{'} ) && $body =~ $INTERPOLATES;
    return ( $body, $interpolates ? 1 : 0 );
}

sub is_sole_subscript_key ($elem) {
    my $stmt = $elem->parent or return 0;
    return 0 unless $stmt->isa('PPI::Statement::Expression') || ref $stmt eq 'PPI::Statement';
    return 0 unless $stmt->schildren == 1;
    my $subscript = $stmt->parent or return 0;
    return 0 unless $subscript->isa('PPI::Structure::Subscript');
    return 0 unless $subscript->start && $subscript->start->content eq '{';
    return $subscript->schildren == 1;
}

1;

# ABSTRACT: PPI helpers for recognising built-in calls and their arguments

__END__

=pod

=head1 DESCRIPTION

C<is_builtin_call($word)> says whether a C<PPI::Token::Word> is used as a
function call rather than a method, hash key, sub name, subscript or part of
a C<package>/C<use>/C<no> statement. C<call_args($word)> returns the call's
arguments as an arrayref of arrayrefs of significant PPI elements, split on
top-level commas. C<is_constant_string($elem)> is true for a quote or heredoc
with nothing interpolated. C<is_sole_subscript_key($elem)> is true when
C<$elem> is the only thing inside a C<{...}> subscript, as in C<$h{'key'}>.
C<command_body($elem)> returns the command text of a backtick or C<qx>
token without its delimiters and whether it interpolates (C<qx'...'> never
does), or an empty list for any other token. S008 and S018 both use it, so
they agree on which commands interpolate.

=cut
