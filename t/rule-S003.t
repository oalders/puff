use v5.36;
use Test2::V0;

use lib 't/lib';
use PuffTest qw( run_corpus );

run_corpus('S003');

subtest 'no free variable name' => sub {
    my $text = join ' ', '$x', '$x_fh', map {"\$x_fh$_"} 2 .. 1000;
    is( Puff::Rule::Security::BarewordFilehandle::_var_name( $text, 'X' ), undef, 'declines' );
    is( Puff::Rule::Security::BarewordFilehandle::_var_name( '', 'X' ), 'x', 'free name' );
};

done_testing;
