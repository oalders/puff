use v5.36;
use Test2::V0;

use Puff::Engine ();
use Puff::Rules  ();
use Puff::Source ();
use Puff::Test   qw( run_corpus );
use Test2::Mock  ();

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
is(
    [ map { $_->message } @{ violations("my \$x = 1;\nmy \$x = 2;\n{ my \$x }\n") } ],
    ['$x shadows the declaration on line 2'],
    'the latest outer declaration is named'
);

# The work done, counted as the calls Puff::LexicalScopes makes to
# refaddr: it compares a scope or element in each step of every walk, so
# the count grows with the time taken but not with the machine's speed.
sub work ($code) {
    my $calls = 0;
    my $mock  = Test2::Mock->new(
        class    => 'Puff::LexicalScopes',
        override => [ refaddr => sub : prototype($) ($ref) { $calls++; Scalar::Util::refaddr($ref) } ],
    );
    my $result = $code->();
    $mock->reset_all;
    return ( $result, $calls );
}

# Nested do blocks reusing one name: no outer $x is visible yet, but a
# block after them sees the file's $x. Checking each outer $x by walking
# up from the declaration was cubic in the depth (500 levels took 11s);
# it is now quadratic: about 90,000 calls here, against 5.5 million.
my $do = 'my $x = 1';
$do = "my \$x = do { $do; \$x }" for 1 .. 200;
my ( $nested, $calls ) = work( sub { violations("$do;\n{ my \$x }\n") } );
is(
    [ map { $_->message } @$nested ], ['$x shadows the declaration on line 1'],
    'deeply nested do blocks: only the block after them is reported'
);
cmp_ok( $calls, '<=', 3 * 200**2, 'nested do blocks are quadratic in the depth' );

# Many declarations of one name in one scope: only the latest is kept, so
# the work is linear in their number. It was quadratic when each
# `my $x = do { my $x }` stepped past every earlier $x of the file.
my $same = ( "my \$x;\n" x 2000 ) . ( "my \$x = do { my \$x };\n" x 2000 ) . "{ my \$x }\n";
( my $redeclared, $calls ) = work( sub { violations($same) } );
is(
    [ map { $_->line . ': ' . $_->message } @$redeclared ],
    ['4001: $x shadows the declaration on line 4000'],
    'many same-scope declarations: the latest is named'
);
cmp_ok( $calls, '<=', 50 * 4000, 'many same-scope declarations are linear' );

# Deep nesting: each block's $y shadows the one around it, the innermost
# $x shadows the file's, and once the blocks close only the file's $x is
# in view.
my $deep = "my \$x;\n" . ( "{ my \$y;\n" x 500 ) . "my \$x;\n" . ( "}\n" x 500 ) . "{ my \$y; my \$x }\n";
is(
    [ map { $_->line } @{ violations($deep) } ],
    [ 3 .. 502, 1003 ], 'nested blocks open and close in order'
);

sub selected (@select) {
    return [ grep { $_ eq 'B008' } map { $_->code } Puff::Rules->instantiate( \@classes, select => [@select] ) ];
}
is( selected( 'S', 'B' ), [], 'not selected by the default prefixes' );
is( selected('B00'), [], 'not selected by a longer prefix' );
is( selected('B008'), ['B008'], 'selected by its exact code' );
is( selected('ALL'), ['B008'], 'selected by ALL' );

done_testing;
