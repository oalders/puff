package Puff::Moose;

use v5.36;

use Exporter     qw( import );
use Scalar::Util qw( refaddr );

our @EXPORT_OK = qw(
    attributes class_include framework imports_nothing package_block package_name package_region
    package_statements same_package
);

# Module => [ family, is a role ].
my %FRAMEWORK = (
    'Moose'       => [ 'Moose', 0 ],
    'Moose::Role' => [ 'Moose', 1 ],
    'Mouse'       => [ 'Mouse', 0 ],
    'Mouse::Role' => [ 'Mouse', 1 ],
    'Moo'         => [ 'Moo', 0 ],
    'Moo::Role'   => [ 'Moo', 1 ],
);

# use Moose (); sets up nothing.
sub imports_nothing ($include) {
    my $list = $include->find_first('PPI::Structure::List') or return 0;
    return 0 unless $list->parent == $include;
    return !$list->schildren;
}

# { module, family, role } when $include is a `use` of Moose, Moose::Role,
# Mouse, Mouse::Role, Moo or Moo::Role that imports its sugar, else undef.
sub framework ($include) {
    return unless $include->isa('PPI::Statement::Include') && ( $include->type // q{} ) eq 'use';
    my $module = $include->module // return;
    my $entry  = $FRAMEWORK{$module} or return;
    return if imports_nothing($include);
    return { module => $module, family => $entry->[0], role => $entry->[1] };
}

# The first statement of $region's package that sets it up as a Moose,
# Mouse or Moo class or role, or undef.
sub class_include ($region) {
    for my $statement ( package_statements($region) ) {
        return $statement if framework($statement);
    }
    return;
}

# The statement that scopes $elem's package: a `package NAME;` statement,
# a `package NAME { }` statement, or the document for package main.
sub package_region ($elem) {
    my $node = $elem;
    while ( my $parent = $node->parent ) {
        my $prev = $node->sprevious_sibling;
        while ($prev) {
            return $prev if $prev->isa('PPI::Statement::Package') && !package_block($prev);
            $prev = $prev->sprevious_sibling;
        }
        my $owner = $parent->parent;
        return $owner if $parent->isa('PPI::Structure::Block') && $owner && $owner->isa('PPI::Statement::Package');
        $node = $parent;
    }
    return $node;
}

sub package_name ($region) {
    return $region->isa('PPI::Statement::Package') ? $region->namespace : 'main';
}

sub same_package ( $region, $other ) {
    return refaddr($region) == refaddr($other);
}

sub package_block ($package) {
    my $last = $package->schild(-1);
    return $last && $last->isa('PPI::Structure::Block') ? $last : undef;
}

# The statements of $region's package, in order.
sub package_statements ($region) {
    if ( $region->isa('PPI::Statement::Package') ) {
        if ( my $block = package_block($region) ) {
            return $block->schildren;
        }
        my @statements;
        my $next = $region->snext_sibling;
        while ( $next && !( $next->isa('PPI::Statement::Package') && !package_block($next) ) ) {
            push @statements, $next;
            $next = $next->snext_sibling;
        }
        return @statements;
    }
    my @statements;
    for my $child ( $region->schildren ) {
        last if $child->isa('PPI::Statement::Package') && !package_block($child);
        push @statements, $child;
    }
    return @statements;
}

# The `has` declarations at the top level of $region's package, as hashes:
#   word    - the `has` token
#   names   - attribute names, or undef when not literal
#   options - { name => [ value tokens ] }, or undef when the option list is
#             not literal key => value pairs (such as `%opts` or `@args`)
sub attributes ($region) {
    my @found;
    for my $statement ( package_statements($region) ) {
        next unless ref $statement eq 'PPI::Statement';
        my $word = $statement->schild(0);
        next unless $word && $word->isa('PPI::Token::Word') && $word->content eq 'has';
        my $args = _has_args($word) or next;
        my ( $name, @rest ) = @$args;
        push @found, { word => $word, names => scalar _names($name), options => scalar _options( \@rest ) };
    }
    return @found;
}

# The arguments of `has`, each an arrayref of elements.
sub _has_args ($word) {
    my @elements;
    my $next = $word->snext_sibling;
    if ( $next && $next->isa('PPI::Structure::List') ) {
        my $after = $next->snext_sibling;
        return unless !$after || ( $after->isa('PPI::Token::Structure') && $after->content eq ';' );
        @elements = _list_elements($next) or return;
    }
    else {
        while ($next) {
            last if $next->isa('PPI::Token::Structure') && $next->content eq ';';
            push @elements, $next;
            $next = $next->snext_sibling;
        }
    }
    my $args = _split( \@elements );
    return @$args ? $args : undef;
}

sub _list_elements ($list) {
    my @statements = $list->schildren;
    return () unless @statements == 1 && $statements[0]->isa('PPI::Statement');
    return $statements[0]->schildren;
}

sub _split ($elements) {
    my @args = ( [] );
    for my $el (@$elements) {
        if ( $el->isa('PPI::Token::Operator') && ( $el->content eq ',' || $el->content eq '=>' ) ) {
            push @args, [];
            next;
        }
        push @{ $args[-1] }, $el;
    }
    pop @args unless @{ $args[-1] };    # trailing comma
    return \@args;
}

sub _string ($token) {
    return $token->content if $token->isa('PPI::Token::Word');
    return $token->string
        if $token->isa('PPI::Token::Quote::Single')
        || $token->isa('PPI::Token::Quote::Literal')
        || ( ( $token->isa('PPI::Token::Quote::Double') || $token->isa('PPI::Token::Quote::Interpolate') )
        && $token->string !~ /[\$\@\\]/ );
    return;
}

# Attribute names from `has NAME`, `has [qw(a b)]` or `has ['a', 'b']`.
sub _names ($arg) {
    return unless $arg && @$arg == 1;
    my $token = $arg->[0];
    if ( $token->isa('PPI::Structure::Constructor') && $token->start->content eq '[' ) {
        my @inner = _list_elements($token) or return;
        my @names;
        for my $item ( @{ _split( \@inner ) } ) {
            return unless @$item == 1;
            if ( $item->[0]->isa('PPI::Token::QuoteLike::Words') ) {
                push @names, $item->[0]->literal;
                next;
            }
            my $name = _string( $item->[0] ) // return;
            push @names, $name;
        }
        return @names ? \@names : undef;
    }
    my $name = _string($token) // return;
    return [$name];
}

sub _options ($rest) {
    my @pairs = @$rest;
    if ( @pairs == 1 && @{ $pairs[0] } == 1 && $pairs[0][0]->isa('PPI::Structure::List') ) {
        my @inner = _list_elements( $pairs[0][0] );
        @pairs = @{ _split( \@inner ) };
    }
    return unless @pairs % 2 == 0;
    my %options;
    while ( my ( $key, $value ) = splice @pairs, 0, 2 ) {
        return unless @$key == 1 && @$value;
        my $name = _string( $key->[0] ) // return;
        $options{$name} = $value;
    }
    return \%options;
}

1;

# ABSTRACT: Find Moose, Mouse and Moo classes, roles and attributes

__END__

=pod

=head1 SYNOPSIS

    use Puff::Moose qw( package_region class_include framework attributes );

    my $region  = package_region($elem);
    my $include = class_include($region) or return;
    my $info    = framework($include);    # { module, family, role }
    for my $attr ( attributes($region) ) { ... }

=head1 DESCRIPTION

Helpers shared by the C<M> rules. A I<region> is the statement that scopes a
package: a C<package NAME;> statement (the package runs until the next one
at the same level), a C<package NAME { ... }> statement, or the document for
package main. Each check works one package at a time.

=over

=item package_region($elem)

The region C<$elem> is in.

=item package_statements($region)

The top-level statements of the region's package, in order.

=item package_block($package)

The block of a C<package NAME { ... }> statement, or undef.

=item package_name($region)

The package's name (C<main> for the document).

=item same_package($region, $other)

Whether two regions are the same.

=item imports_nothing($include)

True for C<use Module ()>.

=item framework($include)

For a C<use> of Moose, Moose::Role, Mouse, Mouse::Role, Moo or Moo::Role
that imports its sugar, a hashref with C<module>, C<family> (C<Moose>,
C<Mouse> or C<Moo>) and C<role> (true for the C<::Role> modules). Undef for
anything else, including C<use Moose ()>.

=item class_include($region)

The first statement of the package for which C<framework> is true, or undef.

=item attributes($region)

The C<has> statements at the top level of the package. Each is a hashref
with C<word> (the C<has> token), C<names> (an arrayref of the literal names
from C<has NAME>, C<has 'NAME'>, C<has [qw(a b)]> or C<has ['a', 'b']>, or
undef) and C<options> (a hashref of option name to the arrayref of tokens in
its value, or undef when the options are not all literal C<< key => value >>
pairs, as with C<%opts> or C<@args>).

=back

=cut
