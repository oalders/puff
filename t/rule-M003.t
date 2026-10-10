use v5.36;
use Test2::V0;

use PPI                                   ();
use Puff::Rule::Moose::LazyWithoutBuilder ();
use Puff::Test                            qw( run_corpus );
use Time::HiRes                           qw( time );

run_corpus('M003');

# The builder lookup walks each package once, not once per attribute, so
# the number of tree searches grows linearly with the number of attributes.
# Returns the number of violations, of tree searches and the seconds taken.
sub check_flat_class ($n) {
    my $code = join q{}, "package My::Big;\nuse Moose;\n",
        map {"has a$_ => ( is => 'ro', lazy => 1, builder => '_b$_' );\nsub _b$_ { 1 }\n"} 1 .. $n;
    my $doc      = PPI::Document->new( \$code );
    my $use      = $doc->find_first('PPI::Statement::Include');
    my $rule     = Puff::Rule::Moose::LazyWithoutBuilder->new;
    my $searches = 0;
    my ( $find, $find_first ) = ( \&PPI::Node::find, \&PPI::Node::find_first );
    no warnings 'redefine';
    local *PPI::Node::find       = sub { $searches++; goto &$find };
    local *PPI::Node::find_first = sub { $searches++; goto &$find_first };
    my $start      = time;
    my @violations = $rule->check( $use, $doc );
    return ( scalar @violations, $searches, time - $start );
}

my ( $small_violations, $small ) = check_flat_class(100);
my ( $big_violations, $big )     = check_flat_class(1000);
is( [ $small_violations, $big_violations ], [ 0, 0 ], 'every builder is found' );
ok( $small > 0, 'the searches are counted' );
ok( $big <= 11 * $small, "searches grow linearly ($small for 100 attributes, $big for 1000)" );

my ( undef, undef, $seconds ) = check_flat_class(2000);
ok( $seconds < 5, "2000 attributes checked in ${seconds}s" );

# Each package's definitions are found without walking into the
# `package NAME { }` blocks nested in it, so deep nesting stays fast. Every
# other package is missing its builder.
sub check_nested_packages ($n) {
    my $code       = join( q{}, map { _nested_package($_) } 1 .. $n ) . "}\n" x $n;
    my $doc        = PPI::Document->new( \$code );
    my $rule       = Puff::Rule::Moose::LazyWithoutBuilder->new;
    my $start      = time;
    my @violations = map { $rule->check( $_, $doc ) } @{ $doc->find('PPI::Statement::Include') };
    return ( scalar @violations, time - $start );
}

sub _nested_package ($i) {
    my $sub = $i % 2 ? "sub _b$i { 1 }\n" : q{};
    return "package P$i {\nuse Moose;\nhas a$i => ( is => 'ro', lazy => 1, builder => '_b$i' );\n$sub";
}

my ( $nested_violations, $nested_seconds ) = check_nested_packages(600);
is( $nested_violations, 300, 'missing builders in nested packages are found' );
ok( $nested_seconds < 5, "600 nested packages checked in ${nested_seconds}s" );

done_testing;
