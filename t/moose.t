use v5.36;
use Test2::V0;

use Path::Tiny   qw( path );
use PPI          ();
use Puff::Engine ();
use Puff::Moose  qw( attributes class_include framework package_name package_region );
use Puff::Rules  ();
use Puff::Source ();

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

# The M rules report the same lines in a CRLF copy of their corpus. The
# engine offers no fix there: PPI and Puff::Source count lines differently
# when there is a CR, so fix offsets would be wrong.
my %rule = map { $_->code => $_ } Puff::Rules->load;
for my $rule_code (qw( M002 M003 M004 M005 )) {
    for my $file ( sort grep { !/\.fixed\.pl\z/ } path( 't', 'corpus', $rule_code )->children(qr/\.pl\z/) ) {
        subtest "CRLF $file" => sub {
            my $lf   = $file->slurp_raw;
            my $crlf = $lf =~ s/\n/\r\n/gr;
            my ( $want, $got ) = map {
                Puff::Engine->new( rules => [ $rule{$rule_code}->new ], fix_mode => $_->[0] )
                    ->process_source( Puff::Source->from_string( $_->[1] ), file => "$file" )
            } [ none => $lf ], [ unsafe => $crlf ];
            is( $got->{error}, undef, 'no error' );
            is(
                [ map { $_->line } @{ $got->{violations} } ], [ map { $_->line } @{ $want->{violations} } ],
                'same lines reported'
            );
            is( [ grep { $_->fixable } @{ $got->{violations} } ], [], 'no fix offered' );
        };
    }
}

done_testing;
