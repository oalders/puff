package Puff::Rule::Moose::LazyWithoutBuilder;

use v5.36;
use parent 'Puff::Rule';

use Scalar::Util qw( refaddr );
use Puff::Moose  qw( attributes class_include framework package_name package_region package_statements same_package );

sub code       {'M003'}
sub summary    {'Lazy attribute has no default or builder'}
sub applies_to {'PPI::Statement::Include'}

sub explanation {
    return <<~'END';
        A lazy attribute builds its value the first time it is read, from
        its `default` or `builder`. Without either there is nothing to
        build it from: Moose and Mouse die when the class is built. Moo
        does not complain; the accessor returns undef unless a value was
        passed to the constructor, so `lazy` does nothing.

            has config => ( is => 'ro', lazy => 1 );                     # reported
            has config => ( is => 'ro', lazy => 1, builder => '_load' ); # fine
            sub _load { ... }

        The rule checks each `has` at the top level of a package that uses
        Moose, Moose::Role, Mouse, Mouse::Role, Moo or Moo::Role. An
        attribute is lazy with `lazy => 1` (any literal true value) or, in
        Moo, `is => 'lazy'`. It is reported when it has no `default` and no
        `builder`, except that Moo's `is => 'lazy'` and Moose's
        `lazy_build => 1` imply the builder `_build_NAME`, so those are not
        reported for that.

        A builder must be a method. When the builder has a known name
        (`builder => '_load'`, Moo's `builder => 1` or `is => 'lazy'`, which
        mean `_build_NAME`) and the package does not define it with
        `sub _load`, `*_load = ...` or `->add_method( _load => ... )`, that
        is reported too. A mention in a comment, POD or a string does not
        count. The method may come from somewhere else when the package
        `extends` a class or consumes roles `with` (also inside a `BEGIN`
        block), sets `@ISA`, uses `parent` or `base`, or is a role itself
        (the consuming class may provide it), so a missing builder is not
        reported in those packages. Nor is it reported when the package may
        define methods under names that are not literal, with
        `*{ EXPR } = ...` or `add_method( $name => ... )`. Other ways of
        getting a method are not seen and are reported: roles applied at
        run time (`apply_all_roles`, `with_roles`, `use roles`),
        `->meta->superclasses(...)`, `handles` delegation, and in-house
        modules that set up inheritance. `lazy_build` builders are not
        checked.

        Not reported: `has '+name'`, a lazy value that is not a literal,
        `builder => sub { ... }`, Moose's `builder => 1` (a method named
        `1`), and a `has` whose name or options are not literal. There is
        no fix.
        END
}

sub check ( $self, $elem, $doc ) {
    my $framework = framework($elem) or return;
    my $region    = package_region($elem);
    my $first     = class_include($region);
    return unless $first && same_package( $first, $elem );
    my $moo = $framework->{family} eq 'Moo';

    my ( @violations, $defs );
    for my $attr ( attributes($region) ) {
        my ( $names, $options ) = @{$attr}{qw( names options )};
        next unless $names && $options;
        next if grep {/\A\+/} @$names;
        next if exists $options->{lazy_build} || exists $options->{default};

        my $is_lazy = $moo && ( _literal( $options->{is} ) // q{} ) eq 'lazy';
        if ( !$is_lazy ) {
            next unless exists $options->{lazy};
            my $lazy = _literal( $options->{lazy} ) // next;
            next unless $lazy;
        }

        my @builders;
        if ( my $builder = $options->{builder} ) {
            my $name = _literal($builder) // next;
            if ( $moo && $name eq '1' ) {
                @builders = map {"_build_$_"} @$names;
            }
            elsif ( $name =~ /\A[A-Za-z_]\w*\z/ ) { @builders = ($name) }
            else                                  {next}
        }
        elsif ($is_lazy) {
            @builders = map {"_build_$_"} @$names;
        }
        else {
            my $what = @$names == 1 ? "attribute $names->[0] has" : 'attributes ' . join( ', ', @$names ) . ' have';
            push @violations, $self->violation( $attr->{word}, message => "Lazy $what no default or builder" );
            next;
        }

        next if $framework->{role};
        $defs //= _definitions($region);
        next if $defs->{may_inherit} || $defs->{dynamic};
        my $package = package_name($region);
        my $skip    = refaddr( $attr->{word}->statement );
        for my $builder (@builders) {
            next if grep { $_ != $skip } @{ $defs->{names}{$builder} // [] };
            push @violations,
                $self->violation(
                $attr->{word},
                message => "Builder $builder for a lazy attribute is not defined in package $package",
                );
        }
    }
    return @violations;
}

# The value of a one-token literal, or undef.
sub _literal ($tokens) {
    return unless $tokens && @$tokens == 1;
    my $token = $tokens->[0];
    return $token->can('literal') ? $token->literal : $token->content if $token->isa('PPI::Token::Number');
    return $token->string
        if $token->isa('PPI::Token::Quote::Single')
        || $token->isa('PPI::Token::Quote::Literal')
        || ( $token->isa('PPI::Token::Quote::Double') && $token->string !~ /[\$\@\\]/ );
    return;
}

# What the package defines and where else it may get methods from, in one
# walk over its statements:
#   names       - { method name => [ refaddr of each statement defining it ] },
#                 from `sub NAME`, `*NAME = ...` and `->add_method( NAME => ... )`
#                 (a mention in a comment, POD or string does not count)
#   may_inherit - true when it extends a class or consumes roles (`extends` or
#                 `with`, also inside BEGIN), uses parent or base, or sets @ISA
#   dynamic     - true when it may define methods whose names are not literal:
#                 `*{ EXPR } = ...` or `add_method` with a non-literal name
sub _definitions ($region) {
    my $package = package_name($region);
    my %defs    = ( names => {}, may_inherit => 0, dynamic => 0 );
    my $add     = sub ( $name, $statement ) {
        $name =~ s/\A\Q$package\E:://;
        push @{ $defs{names}{$name} }, refaddr($statement);
    };
    for my $statement ( package_statements($region) ) {
        if ( $statement->isa('PPI::Statement::Include') ) {
            $defs{may_inherit} = 1 if ( $statement->module // q{} ) =~ /\A(?:parent|base)\z/;
            next;
        }
        my $begin = $statement->isa('PPI::Statement::Scheduled') && $statement->type eq 'BEGIN';
        $defs{may_inherit} = 1 if _extends_or_with($statement);
        my $visit = sub ( $top, $el ) {
            if ( $el->isa('PPI::Statement::Sub') ) {
                $add->( $el->name, $statement ) if defined $el->name;
            }
            elsif ( $el->isa('PPI::Token::Symbol') ) {
                $defs{may_inherit} = 1 if $el->symbol =~ /::ISA\z|\A\@ISA\z/;
                $add->( $1, $statement ) if $el->symbol =~ /\A\*(.+)\z/;
            }
            elsif ( $el->isa('PPI::Token::Cast') && $el->content eq '*' ) {
                my $block = $el->snext_sibling;
                my $op    = $block && $block->snext_sibling;
                $defs{dynamic} = 1
                    if $block
                    && $block->isa('PPI::Structure::Block')
                    && $op
                    && $op->isa('PPI::Token::Operator')
                    && $op->content eq '=';
            }
            elsif ( $el->isa('PPI::Token::Word') && $el->content eq 'add_method' ) {
                my $list = $el->snext_sibling;
                return 0 unless $list && $list->isa('PPI::Structure::List');
                my $arg  = $list->schild(0) && $list->schild(0)->schild(0) or return 0;
                my $name = _literal( [$arg] ) // ( $arg->isa('PPI::Token::Word') ? $arg->content : undef );
                if   ( defined $name ) { $add->( $name, $statement ) }
                else                   { $defs{dynamic} = 1 }
            }
            elsif ( $begin && _extends_or_with($el) ) {
                $defs{may_inherit} = 1;
            }
            return 0;
        };
        $visit->( undef, $statement );
        $statement->find($visit);
    }
    return \%defs;
}

# Whether $el is a statement that starts with `extends` or `with`.
sub _extends_or_with ($el) {
    return 0 unless $el->isa('PPI::Statement');
    my $first = $el->schild(0) or return 0;
    return $first->isa('PPI::Token::Word') && $first->content =~ /\A(?:extends|with)\z/;
}

1;

# ABSTRACT: M003 - Lazy attribute has no default or builder

__END__

=pod

=head1 DESCRIPTION

Reports a lazy attribute (C<< lazy => 1 >>, or Moo's C<< is => 'lazy' >>)
with no C<default> and no C<builder> in a package that uses Moose,
Moose::Role, Mouse, Mouse::Role, Moo or Moo::Role. Moo's C<< is => 'lazy' >>
and Moose's C<< lazy_build => 1 >> imply the builder C<_build_NAME>.

Also reports a lazy attribute whose named builder (C<< builder => 'NAME' >>,
or C<_build_NAME> from Moo's C<< builder => 1 >> or C<< is => 'lazy' >>) is
not defined in the package by C<sub NAME>, C<*NAME = ...> or
C<add_method>; comments, POD and strings do not count. That check is skipped
for roles, for packages that may inherit the method (C<extends> or
C<with>, also inside C<BEGIN>, C<use parent>, C<use base> or C<@ISA>) and
for packages that may define methods under names that are not literal
(C<*{ EXPR } = ...> or C<add_method> with a non-literal name). Roles applied
at run time are not seen. There is no fix.

Not selected by default; select it with C<M> or C<M003>.

=cut
