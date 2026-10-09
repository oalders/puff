use v5.36;
use Test2::V0;

use Puff::Engine ();
use Puff::Rules  ();
use Puff::Source ();
use Puff::Test   qw( run_corpus );

run_corpus('T001');

# The corpus fixes in unsafe mode; check which fixes are safe.
my ($class) = grep { $_->code eq 'T001' } Puff::Rules->load;

sub fix_safely ($text) {
    my $engine = Puff::Engine->new( rules => [ $class->new ], fix_mode => 'safe' );
    my $result = $engine->process_source( Puff::Source->from_string($text), file => 'x.t' );
    return ( $result->{new_text} // $text, [ map { $_->fix_safety } @{ $result->{violations} } ] );
}

subtest 'Test::More: only eq is safe' => sub {
    my ( $text, $left ) = fix_safely("use Test::More;\nok(\$x eq 1);\nok(\$x == 1);\nok(\$x ne 1);\n");
    is( $text, "use Test::More;\nis(\$x, 1);\nok(\$x == 1);\nok(\$x ne 1);\n", 'eq fixed' );
    is( $left, [qw( unsafe unsafe )], '== and ne left as unsafe' );
};

subtest 'Test2::V0: eq is unsafe' => sub {
    my ( $text, $left ) = fix_safely("use Test2::V0;\nok(\$x eq 1);\n");
    is( $text, "use Test2::V0;\nok(\$x eq 1);\n", 'not fixed' );
    is( $left, ['unsafe'], 'reported as unsafe' );
};

subtest 'mixed modules: eq is unsafe' => sub {
    my $orig = "use Test::More;\nuse Test2::Tools::Compare;\nok(\$x eq 1);\n";
    my ( $text, $left ) = fix_safely($orig);
    is( $text, $orig, 'not fixed' );
    is( $left, ['unsafe'], 'unsafe when any is() is not Test::More' );
};

done_testing;
