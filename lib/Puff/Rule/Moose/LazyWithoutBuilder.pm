package Puff::Rule::Moose::LazyWithoutBuilder;

use v5.36;
use parent 'Puff::Rule';

use Puff::Moose qw( attributes class_include framework package_name package_region package_statements same_package );

sub code       {'M003'}
sub summary    {'Lazy attribute has no default or builder'}
sub applies_to {'PPI::Statement::Include'}

sub explanation {
    return <<~'END';
        A lazy attribute builds its value the first time it is read, from
        its `default` or `builder`. Without either there is nothing to
        build it from: Moose and Mouse die when the class is built, and in
        Moo `lazy` does nothing useful.

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
        mean `_build_NAME`) and the name appears nowhere else in the
        package, not even as `sub _load`, that is reported too. The method
        may come from somewhere else when the package `extends` a class,
        consumes roles `with`, sets `@ISA`, uses `parent` or `base`, or is
        a role itself (the consuming class may provide it), so a missing
        builder is not reported in those packages. `lazy_build` builders
        are not checked.

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

    my ( @violations, $may_inherit );
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

        $may_inherit //= $framework->{role} || _may_inherit($region);
        next if $may_inherit;
        my $package = package_name($region);
        for my $builder (@builders) {
            next if _mentioned( $region, $attr->{word}->statement, $builder );
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

# Whether the package extends a class, consumes roles or otherwise gets
# methods from elsewhere.
sub _may_inherit ($region) {
    for my $statement ( package_statements($region) ) {
        if ( $statement->isa('PPI::Statement::Include') ) {
            return 1 if ( $statement->module // q{} ) =~ /\A(?:parent|base)\z/;
            next;
        }
        my $first = $statement->schild(0) or next;
        return 1 if $first->isa('PPI::Token::Word') && $first->content =~ /\A(?:extends|with)\z/;
        return 1
            if $statement->find_first(
            sub ( $top, $el ) { $el->isa('PPI::Token::Symbol') && $el->symbol =~ /::ISA\z|\A\@ISA\z/ } );
    }
    return 0;
}

# Whether $name appears anywhere in the package outside $skip, as in
# `sub NAME`, `*NAME = ...` or `add_method('NAME', ...)`.
sub _mentioned ( $region, $skip, $name ) {
    my $re = qr/(?<!\w)\Q$name\E(?!\w)/;
    for my $statement ( package_statements($region) ) {
        next if $statement == $skip;
        return 1 if $statement->content =~ $re;
    }
    return 0;
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
not mentioned anywhere else in the package. That check is skipped for roles
and for packages that may inherit the method (C<extends>, C<with>,
C<use parent>, C<use base> or C<@ISA>). There is no fix.

Not selected by default; select it with C<M> or C<M003>.

=cut
