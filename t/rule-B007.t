use v5.36;
use Test2::V0;

use Puff::Engine ();
use Puff::Rules  ();
use Puff::Source ();
use Puff::Test   qw( run_corpus );

run_corpus('B007');

my @classes = Puff::Rules->load;
my ($class) = grep { $_->code eq 'B007' } @classes;

sub violations ($text) {
    my $result = Puff::Engine->new( rules => [ $class->new ] )
        ->process_source( Puff::Source->from_string($text), file => 'x.pl' );
    return $result->{violations};
}

my $found = violations("my \$x = 1;\n\nmy \$x = 2;\n");
is(
    [ map { $_->message } @$found ], ['$x is redeclared in the same scope (first declared on line 1)'],
    'message names the variable and the first declaration'
);
is( [ map { $_->fixable ? 1 : 0 } @$found ], [0], 'no fix is offered' );
is( $class->fix_safety, 'none', 'fix safety is none' );
is( [ map { $_->column } @$found ], [4], 'reported at the variable' );

is(
    [ map { $_->line } @{ violations("sub f (\$x, \$y = [ 1, 2 ]) {\n    my \$y;\n    my \$z;\n}\n") } ], [2],
    'a signature PPI reads as a prototype belongs to the body'
);
is( violations("sub f (\$\$) {\n    my \$x;\n}\n"), [], 'a real prototype declares nothing' );
is( violations("package A;\nour \$x;\npackage B;\nour \$x;\n"), [], 'our in different packages' );
is( scalar @{ violations("package A;\nour \$x;\nour \$x;\n") }, 1, 'our twice in one package' );
is(
    [ map { $_->message } @{ violations("my \$x;\nmy \$x;\nmy \$x;\n") } ],
    [ map {"\$x is redeclared in the same scope (first declared on line $_)"} 1, 2 ],
    'each redeclaration names the one before it'
);

# The analysis is linear: thousands of file-level declarations finish well
# inside prove's timeout (it was quadratic in the number of `our`s).
my $many = join q{}, map {"our \$o$_ = 1;\nprint 1;\nmy \$m$_ = 1;\n"} 1 .. 3000;
is(
    [ map { $_->line } @{ violations("${many}our \$o1;\nmy \$m1;\n") } ],
    [ 9001, 9002 ], 'many declarations, two redeclared'
);

sub selected (@select) {
    return [ grep { $_ eq 'B007' } map { $_->code } Puff::Rules->instantiate( \@classes, select => [@select] ) ];
}
is( selected( 'S', 'B' ), [], 'not selected by the default prefixes' );
is( selected('B00'), [], 'not selected by a longer prefix' );
is( selected('B007'), ['B007'], 'selected by its exact code' );
is( selected('ALL'), ['B007'], 'selected by ALL' );

done_testing;
