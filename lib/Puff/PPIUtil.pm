package Puff::PPIUtil;

use v5.36;

use Exporter     qw( import );
use Scalar::Util qw( refaddr );

our @EXPORT_OK = qw(
    is_builtin_call call_args is_constant_string is_sole_subscript_key command_body
    mode_call decimal_mode
);

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

# Builtin => index of the argument that is a permission mode.
my %MODE_ARG = (
    chmod                => 0,
    umask                => 0,
    mkdir                => 1,
    mkfifo               => 1,
    'POSIX::mkfifo'      => 1,
    dbmopen              => 2,
    sysopen              => 3,
    mkpath               => 2,
    'File::Path::mkpath' => 2,
);

# Functions and methods that take a File::Path options hash, and its keys
# that hold a mode.
my %OPTION_FUNCTION = map { $_ => 1 } qw( make_path mkpath File::Path::make_path File::Path::mkpath );
my %OPTION_METHOD   = map { $_ => 1 } qw( mkdir mkpath );
my %MODE_KEY        = map { $_ => 1 } qw( mode chmod mask );

sub mode_call ($elem) {
    if ( my $word = _enclosing_call( $elem, \&_is_mode_builtin ) ) {
        my $name = _name($word);
        my $args = call_args($word);
        return _is_whole_arg( $args, $MODE_ARG{$name}, $elem ) ? $name : undef;
    }
    if ( my $word = _enclosing_call( $elem, \&_is_mode_method ) ) {
        my $args = call_args($word);
        return @$args == 1 && _is_whole_arg( $args, 0, $elem ) ? '->' . $word->content : undef;
    }
    my $ctor = _mode_option_hash($elem)                    // return undef;
    my $word = _enclosing_call( $ctor, \&_is_option_call ) // return undef;
    my $args = _option_call_args($word);
    return undef unless grep { _is_whole_arg( $args, $_, $ctor ) } 0 .. $#$args;
    return _is_method($word) ? '->' . $word->content : _name($word);
}

# Decimal literals whose value is a common mode or umask, so the author
# probably wrote the decimal on purpose: `mkdir $d, 511` is 0777 and
# `umask 18` is 022. decimal_mode never reports these. Many of them have an
# 8 or 9 and are skipped by the digit check anyway; the list keeps the
# exemption in one place whatever the digits.
our @REAL_DECIMAL_MODES = map { oct "0$_" } qw(
    777 775 770 755 750 711 700
    666 664 660 644 640 600 444 400
    22 27 77 2 7
);
my %REAL_DECIMAL_MODE = map { $_ => 1 } @REAL_DECIMAL_MODES;

sub decimal_mode ($elem) {
    return undef unless ref $elem eq 'PPI::Token::Number';
    my $digits = $elem->content;
    return undef unless $digits =~ /\A[1-7][0-7]{1,3}\z/;
    return undef if $REAL_DECIMAL_MODE{$digits};
    my $call = mode_call($elem) // return undef;
    return undef if length $digits == 2 && $call ne 'umask';
    return $call;
}

# call_args, plus f( { ... } ) and f( [...], { ... } ), which PPI parses as
# a plain statement in the list rather than an expression.
sub _option_call_args ($word) {
    my $args = call_args($word);
    return $args if @$args;
    my $list = $word->snext_sibling;
    return [] unless $list && $list->isa('PPI::Structure::List');
    my @statements = grep { ref $_ eq 'PPI::Statement' } $list->schildren;
    return [] unless @statements == 1;
    my @split = ( [] );
    for my $el ( $statements[0]->schildren ) {
        if ( $el->isa('PPI::Token::Operator') && $el->content =~ /\A(?:,|=>)\z/ ) {
            push @split, [];
            next;
        }
        push @{ $split[-1] }, $el;
    }
    return [ grep {@$_} @split ];
}

sub _name ($word) { return $word->content =~ s/\ACORE:://r }

sub _is_method ($word) {
    my $prev = $word->sprevious_sibling;
    return $prev && $prev->isa('PPI::Token::Operator') && $prev->content eq '->' ? 1 : 0;
}

sub _is_mode_builtin ($word) {
    return 0 unless $word->isa('PPI::Token::Word') && exists $MODE_ARG{ _name($word) };
    return is_builtin_call($word);
}

sub _is_mode_method ($word) {
    return $word->isa('PPI::Token::Word') && $word->content eq 'chmod' && _is_method($word) ? 1 : 0;
}

sub _is_option_call ($word) {
    return 0 unless $word->isa('PPI::Token::Word');
    return $OPTION_METHOD{ $word->content }                           ? 1 : 0 if _is_method($word);
    return $OPTION_FUNCTION{ _name($word) } && is_builtin_call($word) ? 1 : 0;
}

sub _is_whole_arg ( $args, $at, $elem ) {
    return 0 unless defined $at && $args->[$at] && @{ $args->[$at] } == 1;
    return refaddr( $args->[$at][0] ) == refaddr($elem);
}

# The call whose arguments include $elem, as f( ..., $elem ) or
# f ..., $elem, when $accept likes its name. Methods need parentheses.
sub _enclosing_call ( $elem, $accept ) {
    my $parent = $elem->parent or return undef;
    if (   ( $parent->isa('PPI::Statement::Expression') || ref $parent eq 'PPI::Statement' )
        && $parent->parent
        && $parent->parent->isa('PPI::Structure::List') ) {
        my $word = $parent->parent->sprevious_sibling;
        return $word && $accept->($word) ? $word : undef;
    }
    my $prev = $elem->sprevious_sibling;
    while ($prev) {
        return _is_method($prev) ? undef : $prev if $accept->($prev);
        return undef if $prev->isa('PPI::Token::Operator') && $prev->content =~ /\A[^=!<>]*=\z/;
        $prev = $prev->sprevious_sibling;
    }
    return undef;
}

# The { ... } hash that holds $elem as the whole value of a mode, chmod or
# mask key.
sub _mode_option_hash ($elem) {
    my $op = $elem->sprevious_sibling or return undef;
    return undef unless $op->isa('PPI::Token::Operator') && $op->content eq '=>';
    my $key = $op->sprevious_sibling or return undef;
    my $name
        = $key->isa('PPI::Token::Word') ? $key->content
        : is_constant_string($key)      ? $key->string
        :                                 return undef;
    return undef unless $MODE_KEY{$name};
    my $before = $key->sprevious_sibling;
    return undef if $before && !( $before->isa('PPI::Token::Operator') && $before->content =~ /\A(?:,|=>)\z/ );
    my $after = $elem->snext_sibling;
    return undef if $after && !( $after->isa('PPI::Token::Operator') && $after->content =~ /\A(?:,|=>)\z/ );
    my $expr = $elem->parent or return undef;
    return undef unless $expr->isa('PPI::Statement::Expression') || ref $expr eq 'PPI::Statement';
    my $ctor = $expr->parent or return undef;
    return undef unless $ctor->isa('PPI::Structure::Constructor') && $ctor->start && $ctor->start->content eq '{';
    return $ctor;
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

C<mode_call($elem)> says whether C<$elem> is the whole of a permission-mode
argument and returns the call's name, or undef. The positions are the mode
argument of C<chmod>, C<umask>, C<mkdir>, C<mkfifo>, C<POSIX::mkfifo>,
C<dbmopen>, C<sysopen> and legacy C<mkpath> (C<CORE::> is dropped from the
name); the sole argument of a C<< ->chmod(...) >> method (returned as
C<< ->chmod >>); and the value of a C<mode>, C<chmod> or C<mask> key in a
C<{ ... }> hash passed to File::Path's C<make_path> or C<mkpath>, or to a
C<< ->mkdir >> or C<< ->mkpath >> method (Path::Tiny). C<decimal_mode($elem)>
returns the same name when C<$elem> is also a decimal literal that was
probably meant as octal: three or four digits, all 0 to 7, or two for
C<umask>. A literal whose decimal value is a common mode or umask (the
decimal of 0777, 0755, 0644, 022 and so on, listed in
C<@Puff::PPIUtil::REAL_DECIMAL_MODES>) is taken as deliberate and is not
returned: C<mkdir $d, 511> sets 0777 on purpose. B003 skips the mode
positions, B010 reports the decimal ones, and S009 checks both their real
value and the octal reading they were probably meant as, so the three agree.

=cut
