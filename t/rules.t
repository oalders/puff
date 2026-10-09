use v5.36;
use Test2::V0;

use Path::Tiny  qw( tempdir );
use Puff::Rules ();

my $tmp = tempdir( CLEANUP => 1, DIR => $ENV{TMPDIR} );

my $n = 0;

sub rule_file ( $dir, $pkg, $code, $extra = '' ) {
    my $file = $dir->child( "R" . $n++ . ".pm" );
    $file->spew_utf8(<<"PM");
package $pkg;
use v5.36;
use parent 'Puff::Rule';
sub code {'$code'}
$extra
1;
PM
    return $file;
}

my $d = $tmp->child('basic');
$d->mkpath;
rule_file( $d, 'T::R::Three', 'Y003' );
rule_file( $d, 'T::R::One', 'Y001', q{sub options { { foo => 0 } }} );
$d->child('sub')->mkpath;
rule_file( $d->child('sub'), 'T::R::Two', 'Y002' );
$d->child('Helper.pm')->spew_utf8("package T::Helper;\n1;\n");

my @classes = grep { $_->code =~ /\AY/ } Puff::Rules->load( rule_paths => ["$d"] );
is( [ map { $_->code } @classes ], [qw( Y001 Y002 Y003 )], 'loaded and sorted by code' );

is(
    [ map { $_->code } Puff::Rules->instantiate( \@classes, select => ['Y'], ignore => ['Y002'] ) ],
    [qw( Y001 Y003 )], 'ignore removes'
);
is(
    [ map { $_->code } Puff::Rules->instantiate( \@classes, select => ['Y00'], ignore => ['Y003'] ) ],
    [qw( Y001 Y002 )], 'prefix select'
);
is(
    [ map { $_->code } Puff::Rules->instantiate( \@classes, select => ['Y001'], extend_select => ['Y003'] ) ],
    [ 'Y001', 'Y003' ], 'extend_select'
);
like(
    dies { Puff::Rules->instantiate( \@classes, select => ['X'] ) },
    qr/\AUnknown rule selector: X\n/, 'select matching no rule dies'
);
like(
    dies { Puff::Rules->instantiate( \@classes, select => ['Y'], extend_select => ['Y9'] ) },
    qr/\AUnknown rule selector: Y9\n/, 'extend_select matching no rule dies'
);
ok( lives { Puff::Rules->instantiate( \@classes, select => [ 'Y', 'P001' ] ) }, 'P001 is a known code' );
is(
    [ map { $_->code } Puff::Rules->instantiate( \@classes, select => ['ALL'] ) ],
    [qw( Y001 Y002 Y003 )], 'ALL selects every rule'
);
is(
    [ map { $_->code } Puff::Rules->instantiate( \@classes, select => ['Y001'], extend_select => ['ALL'] ) ],
    [qw( Y001 Y002 Y003 )], 'ALL in extend_select'
);
is(
    [ map { $_->code } Puff::Rules->instantiate( \@classes, select => ['ALL'], ignore => ['Y002'] ) ],
    [qw( Y001 Y003 )], 'ignore wins over ALL'
);
is( [ Puff::Rules->instantiate( \@classes, select => ['Y'], ignore => ['ALL'] ) ], [], 'ignore ALL' );
ok(
    lives { Puff::Rules->instantiate( \@classes, select => ['Y'], ignore => ['Z'] ) },
    'ignore matching no rule is fine'
);

my ($one) = Puff::Rules->instantiate( \@classes, select => ['Y001'], rule_options => { Y001 => { foo => 5 } } );
is( $one->option('foo'), 5, 'rule option passed' );
like(
    dies { Puff::Rules->instantiate( \@classes, select => ['Y001'], rule_options => { Y001 => { bar => 1 } } ) },
    qr/Unknown option 'bar' for rule Y001/, 'unknown option dies'
);
ok(
    lives { Puff::Rules->instantiate( \@classes, select => ['Y002'], rule_options => { Y001 => { bar => 1 } } ) },
    'options for unselected rule ignored'
);

my $explicit = $tmp->child('explicit');
$explicit->mkpath;
rule_file( $explicit, 'E::On', 'W001' );
rule_file( $explicit, 'E::Off', 'W002', 'sub explicit_select {1}' );
my @wclasses = grep { $_->code =~ /\AW/ } Puff::Rules->load( rule_paths => ["$explicit"] );

sub wcodes (%args) {
    return [ map { $_->code } Puff::Rules->instantiate( \@wclasses, %args ) ];
}
is( wcodes( select => ['W'] ), ['W001'], 'explicit_select rule is not selected by a prefix' );
is( wcodes( select => ['W00'] ), ['W001'], 'nor by a longer prefix' );
is( wcodes( select => ['W'], extend_select => ['W002'] ), [qw( W001 W002 )], 'selected by its exact code' );
is( wcodes( select => ['ALL'] ), [qw( W001 W002 )], 'selected by ALL' );
is( wcodes( select => ['W002'], ignore => ['W'] ), [], 'ignored by a prefix' );
like( dies { wcodes( select => ['W9'] ) }, qr/Unknown rule selector: W9/, 'unknown selectors still die' );

my $dup = $tmp->child('dup');
$dup->mkpath;
rule_file( $dup, 'D::A', 'Y001' );
rule_file( $dup, 'D::B', 'Y001' );
like(
    dies { Puff::Rules->load( rule_paths => ["$dup"] ) }, qr/D::A.*D::B.*Y001|D::B.*D::A.*Y001/,
    'duplicate code names both'
);

my $bad = $tmp->child('bad');
$bad->mkpath;
rule_file( $bad, 'B::Bad', 's1' );
like( dies { Puff::Rules->load( rule_paths => ["$bad"] ) }, qr/B::Bad.*invalid code 's1'/, 'bad code dies' );

my $res = $tmp->child('res');
$res->mkpath;
rule_file( $res, 'B::Res', 'P001' );
like( dies { Puff::Rules->load( rule_paths => ["$res"] ) }, qr/B::Res.*P001.*reserved/, 'P001 reserved' );

my $all = $tmp->child('all');
$all->mkpath;
rule_file( $all, 'B::All', 'ALL001' );
like(
    dies { Puff::Rules->load( rule_paths => ["$all"] ) },
    qr/\ARule B::All uses code ALL001, but the prefix ALL is reserved for selecting every rule\n/,
    'ALL prefix reserved'
);

my $nocode = $tmp->child('nocode');
$nocode->mkpath;
$nocode->child('N.pm')->spew_utf8("package B::NoCode;\nuse parent 'Puff::Rule';\nsub code { undef }\n1;\n");
my $warned = warnings {
    like(
        dies { Puff::Rules->load( rule_paths => ["$nocode"] ) },
        qr/B::NoCode has invalid code 'undef'/, 'undef code named in message'
    )
};
is( $warned, [], 'no uninitialized warning' );

# Module::Pluggable discovery
my $lib = $tmp->child('lib');
$lib->child(qw( Puff Rule Fake ))->mkpath;
$lib->child(qw( Puff Rule Fake Found.pm ))->spew_utf8(<<'PM');
package Puff::Rule::Fake::Found;
use v5.36;
use parent 'Puff::Rule';
sub code {'Z001'}
1;
PM
$lib->child(qw( Puff Rule Fake NotARule.pm ))->spew_utf8("package Puff::Rule::Fake::NotARule;\n1;\n");
unshift @INC, "$lib";
is( [ grep {/\AZ/} map { $_->code } Puff::Rules->load( rule_paths => [] ) ], ['Z001'], 'pluggable discovery' );

like( dies { Puff::Rules->load( rule_paths => ["$tmp/nope"] ) }, qr/not a directory/, 'missing rule path' );

# A built-in rule that does not compile is an error, not a warning.
my $broken = $tmp->child('broken-lib');
$broken->child(qw( Puff Rule Fake2 ))->mkpath;
$broken->child(qw( Puff Rule Fake2 Broken.pm ))->spew_utf8("package Puff::Rule::Fake2::Broken;\nsub {\n");
{
    local @INC = ( "$broken", @INC );
    my $err;
    my $w = warnings {
        $err = dies { Puff::Rules->load }
    };
    like( $err, qr/Puff::Rule::Fake2::Broken/, 'broken built-in rule dies, naming it' );
    is( $w, [], 'and does not just warn' );
}

done_testing;
