use v5.36;
use Test2::V0;

use PPI                                   ();
use Puff::Rule::Moose::LazyWithoutBuilder ();
use Puff::Test                            qw( run_corpus );
use Time::HiRes                           qw( time );

run_corpus('M003');

# The builder lookup walks each package once, not once per attribute, so
# the number of tree searches grows linearly with the number of attributes.
sub violations_searches_seconds ($n) {
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

my ( $small_violations, $small ) = violations_searches_seconds(100);
my ( $big_violations, $big )     = violations_searches_seconds(1000);
is( [ $small_violations, $big_violations ], [ 0, 0 ], 'every builder is found' );
ok( $big <= 11 * $small, "searches grow linearly ($small for 100 attributes, $big for 1000)" );

my ( undef, undef, $seconds ) = violations_searches_seconds(2000);
ok( $seconds < 5, "2000 attributes checked in ${seconds}s" );

done_testing;
