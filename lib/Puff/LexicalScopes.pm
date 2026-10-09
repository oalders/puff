package Puff::LexicalScopes;

use v5.36;

use Exporter     qw( import );
use Scalar::Util qw( refaddr weaken );

our @EXPORT_OK = qw( conflicts_at );

my %DECLARATOR = map { $_ => 1 } qw( my our state );

# The conflicts reported at $elem, a variable token or a signature: a list
# of { kind => 'redeclared' or 'shadowed', symbol => '$x', line => N }.
sub conflicts_at ( $elem, $doc ) {
    return @{ _conflicts($doc)->{ refaddr $elem } // [] };
}

# The analysis depends only on the whole document, so it is done once per
# document and shared by both rules that use it. The weakened reference goes
# undef when the document is freed, so a re-parsed document never sees
# another document's answers (fixes are text edits; a document is never
# changed in place).
my ( $cached_doc, $cached );

sub _conflicts ($doc) {
    return $cached if $cached_doc && refaddr($cached_doc) == refaddr($doc);
    $cached_doc = $doc;
    weaken($cached_doc);
    $cached = _analyse($doc);
    return $cached;
}

# Walks the declarations in document order. Each scope (the document, a
# block, or a compound statement for the variables in its condition or
# loop header) keeps the names declared in it so far, so a name found in
# the declaration's own scope is redeclared and one found in an enclosing
# scope is shadowed.
sub _analyse ($doc) {
    my ( %declared, %found );
    for my $token ( $doc->tokens ) {
        for my $decl ( _declarations($token) ) {
            my $conflict = _check( \%declared, $decl ) or next;
            push @{ $found{ refaddr $decl->{elem} } }, $conflict;
        }
    }
    return \%found;
}

sub _check ( $declared, $decl ) {
    my $symbol = $decl->{symbol};
    my $own    = $declared->{ refaddr $decl->{scope} } //= {};
    if ( my $earlier = $own->{$symbol} ) {
        if ( _different_globals( $earlier, $decl ) ) {
            $own->{$symbol} = $decl;
            return;
        }
        return { kind => 'redeclared', symbol => $symbol, line => $earlier->{line} };
    }
    $own->{$symbol} = $decl;

    for ( my $scope = $decl->{scope}->parent ; $scope ; $scope = $scope->parent ) {
        next unless _is_scope($scope);
        my $earlier = ( $declared->{ refaddr $scope } // {} )->{$symbol} or next;

        # `my $x = do { my $x ... }`: the outer $x is not visible yet.
        next if $earlier->{statement} && _contains( $earlier->{statement}, $decl->{elem} );

        # An inner `our` of a name already declared with `our` is the same
        # global or, in another package, a different one on purpose.
        return if $earlier->{kind} eq 'our' && $decl->{kind} eq 'our';
        return { kind => 'shadowed', symbol => $symbol, line => $earlier->{line} };
    }
    return;
}

# Two `our` declarations in different packages name different globals.
sub _different_globals ( $earlier, $decl ) {
    return $earlier->{kind} eq 'our' && $decl->{kind} eq 'our' && $earlier->{package} ne $decl->{package};
}

sub _is_scope ($elem) {
    return
           $elem->isa('PPI::Structure::Block')
        || $elem->isa('PPI::Document')
        || $elem->isa('PPI::Statement::Compound');
}

sub _contains ( $outer, $elem ) {
    for ( my $el = $elem ; $el ; $el = $el->parent ) {
        return 1 if refaddr($el) == refaddr($outer);
    }
    return 0;
}

# The declarations a token starts: the variables after my/our/state, or the
# parameters of a sub signature (one token holding them all, or one symbol
# token per parameter, depending on how PPI parsed it).
sub _declarations ($token) {
    return _signature($token) if $token->isa('PPI::Token::Prototype');
    return _signature_param($token) if $token->isa('PPI::Token::Symbol');
    return unless $token->isa('PPI::Token::Word') && $DECLARATOR{ $token->content };
    my $prev = $token->sprevious_sibling;
    return if $prev && $prev->isa('PPI::Token::Operator') && $prev->content eq '->';
    my $what = $token->snext_sibling or return;
    my @vars
        = $what->isa('PPI::Token::Symbol')   ? ($what)
        : $what->isa('PPI::Structure::List') ? @{ $what->find('PPI::Token::Symbol') || [] }
        :                                      ();
    return unless @vars;

    my $scope = _scope_of($token) or return;
    my $stmt  = $token->statement;
    $stmt = undef if $stmt && $stmt->isa('PPI::Statement::Compound');    # for my $x (...) { }
    my $package = $token->content eq 'our' ? _package_of($token) : q{};
    return map {
        +{
            elem      => $_,
            symbol    => $_->symbol,
            kind      => $token->content eq 'our' ? 'our' : 'my',
            package   => $package,
            line      => $_->line_number,
            scope     => $scope,
            statement => $stmt,
        }
    } @vars;
}

# The nearest block, document or compound statement around $token. A
# variable declared in an `if` or `while` condition or a `for` header
# belongs to the compound statement, so it is visible in all its blocks.
sub _scope_of ($token) {
    for ( my $el = $token->parent ; $el ; $el = $el->parent ) {
        return $el if _is_scope($el);
    }
    return;
}

# The parameters of `sub f ($x, $y = 1) { ... }`, which belong to the body.
# A prototype such as `($$;@)` has no names and declares nothing.
sub _signature ($token) {
    my $body = $token->snext_sibling;
    $body = $body->snext_sibling while $body && !$body->isa('PPI::Structure::Block') && !_ends_sub($body);
    return unless $body && $body->isa('PPI::Structure::Block');
    my $text = $token->content =~ s/\A\(|\)\z//gr;
    return map {
        +{
            elem      => $token,
            symbol    => $_,
            kind      => 'my',
            package   => q{},
            line      => $token->line_number,
            scope     => $body,
            statement => undef,
        }
    } grep {defined} map { /\A\s*([\$\@%]\w+)/ ? $1 : undef } _split_params($text);
}

# A parameter in a signature that PPI parsed as a structure: a
# PPI::Structure::Signature after a named sub, or a list after `sub` in an
# anonymous sub. Symbols in default values are not parameters.
sub _signature_param ($token) {
    my $prev = $token->sprevious_sibling;
    return if $prev && !( $prev->isa('PPI::Token::Operator') && $prev->content eq ',' );
    my $expr   = $token->parent or return;
    my $struct = $expr->isa('PPI::Statement') ? $expr->parent : $expr;
    return unless $struct;
    my $is_signature = $struct->isa('PPI::Structure::Signature');
    if ( !$is_signature && $struct->isa('PPI::Structure::List') ) {
        my $word = $struct->sprevious_sibling;
        $is_signature = $word && $word->isa('PPI::Token::Word') && $word->content eq 'sub';
    }
    return unless $is_signature;
    my $body = $struct->snext_sibling;
    $body = $body->snext_sibling while $body && !$body->isa('PPI::Structure::Block') && !_ends_sub($body);
    return unless $body && $body->isa('PPI::Structure::Block');
    return {
        elem      => $token,
        symbol    => $token->symbol,
        kind      => 'my',
        package   => q{},
        line      => $token->line_number,
        scope     => $body,
        statement => undef,
    };
}

sub _ends_sub ($elem) {
    return $elem->isa('PPI::Token::Structure') && $elem->content eq ';';
}

# Splits a signature on the commas that are not inside brackets, so a
# default such as `$x = [ $y, $z ]` stays one parameter.
sub _split_params ($text) {
    my @params;
    my $current = q{};
    my $depth   = 0;
    for my $char ( split //, $text ) {
        if ( $char eq ',' && !$depth ) {
            push @params, $current;
            $current = q{};
            next;
        }
        $depth++ if $char =~ /[\(\[\{]/;
        $depth-- if $char =~ /[\)\]\}]/ && $depth;
        $current .= $char;
    }
    return ( @params, $current );
}

# The package in effect at $token: the nearest enclosing `package NAME {`
# block, or the last `package NAME;` before it in an enclosing scope.
sub _package_of ($token) {
    for ( my $el = $token ; $el ; $el = $el->parent ) {
        return $el->namespace if $el->isa('PPI::Statement::Package');
        for ( my $prev = $el->sprevious_sibling ; $prev ; $prev = $prev->sprevious_sibling ) {
            return $prev->namespace
                if $prev->isa('PPI::Statement::Package') && !$prev->find_first('PPI::Structure::Block');
        }
    }
    return 'main';
}

1;

# ABSTRACT: Find lexical variables declared twice in a scope or shadowed

__END__

=pod

=head1 SYNOPSIS

    use Puff::LexicalScopes qw( conflicts_at );

    for my $conflict ( conflicts_at( $symbol_token, $doc ) ) {
        say "$conflict->{symbol} $conflict->{kind} (line $conflict->{line})";
    }

=head1 DESCRIPTION

The analysis behind B007 (a lexical redeclared in the same scope) and B008
(a lexical that shadows one from an enclosing scope).

C<conflicts_at($elem, $doc)> returns the conflicts reported at C<$elem>, a
L<PPI::Token::Symbol> in a C<my>, C<our> or C<state> declaration or a
L<PPI::Token::Prototype> holding a sub signature, or a signature parameter. Each is a hash reference
with C<kind> (C<redeclared> or C<shadowed>), C<symbol> (such as C<$x>) and
C<line>, the line of the earlier declaration. The whole document is
analysed on the first call and the answer is kept until a different
document is passed.

Scopes are the document, every block, and each compound statement, which
holds the variables declared in its condition or loop header so that they
are visible in all of its blocks. Signature parameters belong to the sub's
body block. C<local> declares nothing. Two C<our> declarations of the same
name are reported only when they are in the same scope and package; in
nested scopes they name the same global, and in different packages
different ones.

=cut
