use v5.36;
use Test2::V0;

use Puff::Engine ();
use Puff::Rules  ();
use Puff::Source ();
use Puff::Test   qw( run_corpus );

run_corpus('A001');

sub codes_with ( $options, $text ) {
    my ($class) = grep { $_->code eq 'A001' } Puff::Rules->load;
    my $rule = $class->new( options => $options );
    my $result
        = Puff::Engine->new( rules => [$rule] )->process_source( Puff::Source->from_string($text), file => 'x.pl' );
    return [ map { $_->line } @{ $result->{violations} } ];
}

is( codes_with( {}, "pairfoo { \$a } 1;\n" ), [1], 'unknown pair function is reported' );
is(
    codes_with( { 'extra-pair-functions' => ['pairfoo'] }, "pairfoo { \$a } 1;\nX::pairfoo { \$b } 1;\n" ),
    [], 'extra-pair-functions allows them'
);
like(
    dies { codes_with( { 'extra-pair-functions' => 'pairfoo' }, "1;\n" ) },
    qr/extra-pair-functions must be a list/, 'a string is rejected'
);

done_testing;
