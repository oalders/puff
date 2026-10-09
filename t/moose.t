use v5.36;
use Test2::V0;

use PPI         ();
use Puff::Moose qw( attributes class_include framework package_name package_region );

my $code = <<'END';
package Foo;
use Moose;
has x => ( is => 'ro', default => sub { 1 } );
has [qw(a b)] => ( isa => 'Int' );
has c => %opts;
package Bar {
    use Moo::Role;
}
package Baz;
use Mouse ();
END

my $doc      = PPI::Document->new( \$code );
my @includes = @{ $doc->find('PPI::Statement::Include') };

is( framework( $includes[0] ), { module => 'Moose', family => 'Moose', role => 0 }, 'use Moose' );
is( framework( $includes[1] ), { module => 'Moo::Role', family => 'Moo', role => 1 }, 'use Moo::Role' );
is( framework( $includes[2] ), undef, 'use Mouse () sets up nothing' );

is( [ map { package_name( package_region($_) ) } @includes ], [qw( Foo Bar Baz )], 'package of each use' );
is( class_include( package_region( $includes[2] ) ), undef, 'Baz is not a class' );

my @attrs = attributes( package_region( $includes[0] ) );
is(
    [ map { [ $_->{names}, $_->{options} ? [ sort keys %{ $_->{options} } ] : undef ] } @attrs ],
    [ [ ['x'], [qw( default is )] ], [ [qw( a b )], ['isa'] ], [ ['c'], undef ] ],
    'attributes of Foo',
);

done_testing;
