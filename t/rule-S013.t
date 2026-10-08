use v5.36;
use Test2::V0;

use Puff::Engine ();
use Puff::Rules  ();
use Puff::Source ();
use Puff::Test qw( run_corpus );

run_corpus('S013');

sub lines_with ( $options, $text ) {
    my ($class) = grep { $_->code eq 'S013' } Puff::Rules->load;
    my $engine  = Puff::Engine->new( rules => [ $class->new( options => $options ) ] );
    my $result  = $engine->process_source( Puff::Source->from_string($text), file => 'x.pl' );
    return [ map { $_->line } @{ $result->{violations} } ];
}

my $lower = qq{my \$sql = "select * from users where id = \$id";\n};
is( lines_with( {}, $lower ), [1], 'lower-case SQL is reported by default' );
is( lines_with( { 'upper-case-keywords' => 1 }, $lower ), [], 'and ignored with upper-case-keywords' );

my $escaped = qq{my \$sql = "SELECT * FROM t WHERE id = " . esc(\$id);\n};
is( lines_with( {}, $escaped ), [1], 'an unknown function is reported' );
is( lines_with( { 'safe-functions' => ['esc'] }, $escaped ), [], 'safe-functions' );

my $quoted = qq{my \$sql = "SELECT * FROM t WHERE id = " . \$db->esc(\$id);\n};
is( lines_with( {}, $quoted ), [1], 'an unknown method is reported' );
is( lines_with( { 'quoting-methods' => ['esc'] }, $quoted ), [], 'quoting-methods' );

done_testing;
