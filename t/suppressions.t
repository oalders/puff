use v5.36;
use Test2::V0;

use PPI ();
use Puff::Suppressions;

sub sup ($code) { Puff::Suppressions->new( PPI::Document->new( \$code ) ) }

my $s = sup("my \$x = rand(); # puff: ignore S001\nmy \$y = rand();\n");
ok $s->is_suppressed( 'S001', 1 ),  'line ignore matches';
ok !$s->is_suppressed( 'S002', 1 ), 'other code not suppressed';
ok !$s->is_suppressed( 'S001', 2 ), 'other line not suppressed';
is $s->problems, [], 'no problems';

$s = sup("foo(); # puff: ignore S001, S002\nbar(); # puff: ignore S\n");
ok $s->is_suppressed( 'S001', 1 ),  'first code';
ok $s->is_suppressed( 'S002', 1 ),  'second code';
ok !$s->is_suppressed( 'S003', 1 ), 'unlisted';
ok $s->is_suppressed( 'S003', 2 ),  'prefix S';
ok !$s->is_suppressed( 'B001', 2 ), 'prefix does not match other letter';

$s = sup("# puff: ignore-file S00\nfoo();\n\nbar();\n");
ok $s->is_suppressed( 'S001', $_ ), "file ignore line $_" for 1 .. 4;
ok !$s->is_suppressed( 'S010', 2 ), 'S00 does not match S010';

$s = sup("foo();\n    # puff: ignore\n# puff: ignore-file\n");
ok !$s->is_suppressed( 'S001', 2 ), 'bare ignore suppresses nothing';
is $s->problems,
    [
    { line => 2, column => 5, message => 'suppression comment must list codes' },
    { line => 3, column => 1, message => 'suppression comment must list codes' },
    ],
    'P001 problems';

$s = sup(qq{my \$s = "# puff: ignore S001";\n});
ok !$s->is_suppressed( 'S001', 1 ), 'string content ignored';
is $s->problems, [], 'no problems from string';

done_testing;
