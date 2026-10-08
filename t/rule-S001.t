use v5.36;
use Test2::V0;

use lib 't/lib';
use PuffTest qw( run_corpus );

run_corpus('S001');

done_testing;
