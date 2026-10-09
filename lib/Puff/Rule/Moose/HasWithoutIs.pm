package Puff::Rule::Moose::HasWithoutIs;

use v5.36;
use parent 'Puff::Rule';

use Puff::Moose qw( attributes class_include framework package_region same_package );

sub code       {'M002'}
sub summary    {'Attribute declared with has but no is'}
sub applies_to {'PPI::Statement::Include'}

# Options that give a Moose or Mouse attribute a method of its own.
my @METHOD_OPTIONS = qw( reader writer accessor predicate clearer handles );

sub explanation {
    return <<~'END';
        `has` without `is` does not do what it looks like. In Moose and
        Mouse the attribute gets no accessor, so `$obj->name` dies (Moose
        only warns when the class is built). In Moo `is` is required, and
        the class dies when it is compiled.

            has name => ( isa => 'Str' );               # reported
            has name => ( is => 'ro', isa => 'Str' );   # fine

        The rule checks each `has` at the top level of a package that uses
        Moose, Moose::Role, Mouse, Mouse::Role, Moo or Moo::Role, in
        `has NAME => (...)`, `has 'NAME', ...`, `has [qw(a b)] => (...)` and
        `has(...)` form. Packages are checked one at a time.

        In a Moose or Mouse package an attribute with `reader`, `writer`,
        `accessor`, `predicate`, `clearer` or `handles` is not reported:
        it has a method, and Moose does not warn about it. Write
        `is => 'bare'` to say an attribute needs no accessor. In a Moo
        package `is` is required whatever else is given, so those are
        reported; Moo's choices are `ro`, `rw`, `rwp`, `lazy` and `bare`.

        Not reported: `has '+name' => (...)`, which changes an inherited
        attribute, and a `has` whose name or options are not literal (a
        variable, `%opts`, `@args`, or a function call). There is no fix.
        END
}

sub check ( $self, $elem, $doc ) {
    my $framework = framework($elem) or return;
    my $region    = package_region($elem);
    my $first     = class_include($region);
    return unless $first && same_package( $first, $elem );

    my @violations;
    for my $attr ( attributes($region) ) {
        my ( $names, $options ) = @{$attr}{qw( names options )};
        next unless $names && $options;
        next if grep {/\A\+/} @$names;
        next if exists $options->{is};
        next if $framework->{family} ne 'Moo' && grep { exists $options->{$_} } @METHOD_OPTIONS;

        my $what = @$names == 1 ? "Attribute $names->[0] has" : 'Attributes ' . join( ', ', @$names ) . ' have';
        my $why
            = $framework->{family} eq 'Moo'
            ? "; $framework->{module} requires it"
            : ', so no accessor is generated';
        push @violations, $self->violation( $attr->{word}, message => "$what no is option$why" );
    }
    return @violations;
}

1;

# ABSTRACT: M002 - Attribute declared with has but no is

__END__

=pod

=head1 DESCRIPTION

Reports C<has> without C<is> in a package that uses Moose, Moose::Role,
Mouse, Mouse::Role, Moo or Moo::Role. Moose and Mouse create no accessor for
such an attribute; Moo dies because C<is> is required there.

In Moose and Mouse packages, an attribute with C<reader>, C<writer>,
C<accessor>, C<predicate>, C<clearer> or C<handles> is not reported, which
matches when Moose warns. In Moo packages it still is. C<has '+name'> and
C<has> with options that are not literal C<< key => value >> pairs are not
reported. There is no fix.

Not selected by default; select it with C<M> or C<M002>.

=cut
