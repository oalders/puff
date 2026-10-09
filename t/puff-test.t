use v5.36;
use Test2::V0;

use Puff::Test qw( run_corpus );

run_corpus( 'X001', rule_paths => ['t/lib-rules'], dir => 't/corpus/X001' );

like( dies { run_corpus('X001') }, qr/\ANo rule with code X001\n/, 'rule outside @INC needs rule_paths' );
like(
    dies { run_corpus( 'X001', rule_paths => ['t/lib-rules'], dir => 't/corpus/none' ) },
    qr/\ACorpus directory t\/corpus\/none does not exist\n/, 'missing dir'
);

done_testing;
