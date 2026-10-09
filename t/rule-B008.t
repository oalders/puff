use v5.36;
use Test2::V0;

use Puff::Engine ();
use Puff::Rules  ();
use Puff::Source ();
use Puff::Test   qw( run_corpus );

run_corpus('B008');

my @classes = Puff::Rules->load;
my ($class) = grep { $_->code eq 'B008' } @classes;

sub violations ($text) {
    my $result = Puff::Engine->new( rules => [ $class->new ] )
        ->process_source( Puff::Source->from_string($text), file => 'x.pl' );
    return $result->{violations};
}

my $found = violations("my \$x = 1;\n\n{ my \$x = 2 }\n");
is(
    [ map { $_->message } @$found ], ['$x shadows the declaration on line 1'],
    'message names the variable and the first declaration'
);
is( [ map { $_->fixable ? 1 : 0 } @$found ], [0], 'no fix is offered' );
is( $class->fix_safety, 'none', 'fix safety is none' );
is( [ map { $_->column } @$found ], [6], 'reported at the variable' );

is(
    [ map { $_->line } @{ violations("my \$x;\nmy \$y;\nsub f (\$x, \$z = \$y) { 1 }\n") } ], [3],
    'a signature PPI reads as a prototype: parameters only'
);
is(
    [ map { $_->line } @{ violations("for ( my \$i = 0 ; \$i < 2 ; \$i++ ) {\n    my \$i = 1;\n}\n") } ], [2],
    'C-style for loop variable'
);
is( violations("package A;\nour \$x;\npackage B;\n{ our \$x }\n"), [], 'inner our of an outer our' );

sub selected (@select) {
    return [ grep { $_ eq 'B008' } map { $_->code } Puff::Rules->instantiate( \@classes, select => [@select] ) ];
}
is( selected( 'S', 'B' ), [], 'not selected by the default prefixes' );
is( selected('B00'), [], 'not selected by a longer prefix' );
is( selected('B008'), ['B008'], 'selected by its exact code' );
is( selected('ALL'), ['B008'], 'selected by ALL' );

done_testing;
