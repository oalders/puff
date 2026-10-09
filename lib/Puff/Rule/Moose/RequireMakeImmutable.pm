package Puff::Rule::Moose::RequireMakeImmutable;

use v5.36;
use parent 'Puff::Rule';

use Puff::Moose qw( imports_nothing package_name package_region package_statements same_package );

sub code       {'M001'}
sub summary    {'Moose class never calls make_immutable'}
sub applies_to {'PPI::Statement::Include'}
sub fix_safety {'unsafe'}
sub options    { { modules => [ 'Moose', 'Mouse' ] } }

sub explanation {
    return <<~'END';
        A Moose class stays mutable until you call make_immutable. A
        mutable class builds its constructor and accessors at runtime, so
        every `new` is slower than it needs to be. When the class is
        finished, say so:

            __PACKAGE__->meta->make_immutable;

        The rule reports `use Moose` (or another module in the `modules`
        option) when the package it is in never calls `->make_immutable`.
        Packages are checked one at a time, so a file with two classes
        needs two calls. Any `->make_immutable` call in the package counts,
        such as `$meta->make_immutable`. `use Moose ()`, which does not set
        up a class, and roles are not reported.

        The fix inserts `__PACKAGE__->meta->make_immutable;` before the `1;`
        that ends the package, and is not offered when the package does
        not end with `1;`. It is unsafe because code that changes the class
        after it is loaded (adding attributes or applying roles at runtime)
        dies once the class is immutable.

        Option `modules` (default `["Moose", "Mouse"]`): modules that make
        the package a Moose-style class. Add your own Moose::Exporter
        modules here.
        END
}

sub check ( $self, $elem, $doc ) {
    return unless ( $elem->type // q{} ) eq 'use';
    my $module = $elem->module // return;
    return unless grep { $_ eq $module } @{ $self->option('modules') };
    return if imports_nothing($elem);
    my $region = package_region($elem);
    return if _makes_immutable( $doc, $region );
    my $name = package_name($region);
    return $self->violation(
        $elem,
        message => "Package $name uses $module but never calls __PACKAGE__->meta->make_immutable",
        fixable => defined _final_true($region) ? 1 : 0,
    );
}

sub fix ( $self, $violation, $fix ) {
    my $one    = _final_true( package_region( $violation->element ) ) // return 0;
    my $indent = q{ } x ( $one->location->[1] - 1 );
    $fix->insert_before( $one, "__PACKAGE__->meta->make_immutable;\n\n$indent" );
    return 1;
}

sub _makes_immutable ( $doc, $region ) {
    my $calls = $doc->find(
        sub ( $top, $el ) {
            return 0 unless $el->isa('PPI::Token::Word') && $el->content eq 'make_immutable';
            my $arrow = $el->sprevious_sibling;
            return $arrow && $arrow->isa('PPI::Token::Operator') && $arrow->content eq '->';
        }
    ) or return 0;
    return grep { same_package( package_region($_), $region ) } @$calls;
}

# The `1;` statement that ends the package, or undef.
sub _final_true ($region) {
    my @statements
        = grep { !$_->isa('PPI::Statement::End') && !$_->isa('PPI::Statement::Data') } package_statements($region);
    my $last   = $statements[-1] or return;
    my @tokens = $last->schildren;
    return unless @tokens == 2 && $tokens[0]->isa('PPI::Token::Number') && $tokens[0]->content eq '1';
    return unless $tokens[1]->isa('PPI::Token::Structure') && $tokens[1]->content eq ';';
    return $last;
}

1;

# ABSTRACT: M001 - Moose class never calls make_immutable

__END__

=pod

=head1 DESCRIPTION

Reports C<use Moose> (or another module named in the C<modules> option) in
a package that never calls C<< ->make_immutable >>. The unsafe fix inserts
C<< __PACKAGE__->meta->make_immutable; >> before the package's final C<1;>.

Based on L<Perl::Critic::Policy::Moose::RequireMakeImmutable>, which checks
the whole file rather than each package.

Not selected by default; select it with C<M> or C<M001>.

=cut
