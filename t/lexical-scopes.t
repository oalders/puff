use v5.36;
use Test2::V0;

use PPI                 ();
use Puff::LexicalScopes qw( conflicts_at );

# The last variable token of $doc.
sub last_symbol ($doc) {
    return $doc->find('PPI::Token::Symbol')->[-1];
}

# The answer is cached in one slot, so calls that switch between two
# documents analyse each again but still get that document's answer.
my $one = PPI::Document->new( \"my \$x;\nmy \$x;\n" );
my $two = PPI::Document->new( \"my \$y;\n{\n    my \$y;\n}\n" );
for my $round ( 1, 2 ) {
    is(
        [ conflicts_at( last_symbol($one), $one ) ],
        [ { kind => 'redeclared', symbol => '$x', line => 1 } ],
        "round $round: the first document's conflict"
    );
    is(
        [ conflicts_at( last_symbol($two), $two ) ],
        [ { kind => 'shadowed', symbol => '$y', line => 1 } ],
        "round $round: the second document's conflict"
    );
    is( [ conflicts_at( $one->find('PPI::Token::Symbol')->[0], $one ) ], [], "round $round: none at the first \$x" );
}

done_testing;
