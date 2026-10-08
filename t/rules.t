use v5.36;
use Test2::V0;

use Path::Tiny qw( tempdir );
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
rule_file( $d, 'T::R::Three', 'T003' );
rule_file( $d, 'T::R::One',   'T001', q{sub options { { foo => 0 } }} );
$d->child('sub')->mkpath;
rule_file( $d->child('sub'), 'T::R::Two', 'T002' );
$d->child('Helper.pm')->spew_utf8("package T::Helper;\n1;\n");

my @classes = grep { $_->code =~ /\AT/ } Puff::Rules->load( rule_paths => ["$d"] );
is( [ map { $_->code } @classes ], [qw( T001 T002 T003 )], 'loaded and sorted by code' );

is( [ map { $_->code } Puff::Rules->instantiate( \@classes, select => ['T'], ignore => ['T002'] ) ],
    [qw( T001 T003 )], 'ignore removes' );
is( [ map { $_->code } Puff::Rules->instantiate( \@classes, select => ['T00'], ignore => ['T003'] ) ],
    [qw( T001 T002 )], 'prefix select' );
is( [ map { $_->code } Puff::Rules->instantiate( \@classes, select => ['X'], extend_select => ['T003'] ) ],
    ['T003'], 'extend_select' );
is( [ Puff::Rules->instantiate( \@classes, select => ['X'] ) ], [], 'nothing selected' );

my ($one) = Puff::Rules->instantiate( \@classes, select => ['T001'], rule_options => { T001 => { foo => 5 } } );
is( $one->option('foo'), 5, 'rule option passed' );
like( dies { Puff::Rules->instantiate( \@classes, select => ['T001'], rule_options => { T001 => { bar => 1 } } ) },
    qr/Unknown option 'bar' for rule T001/, 'unknown option dies' );
ok( lives { Puff::Rules->instantiate( \@classes, select => ['T002'], rule_options => { T001 => { bar => 1 } } ) },
    'options for unselected rule ignored' );

my $dup = $tmp->child('dup');
$dup->mkpath;
rule_file( $dup, 'D::A', 'T001' );
rule_file( $dup, 'D::B', 'T001' );
like( dies { Puff::Rules->load( rule_paths => ["$dup"] ) }, qr/D::A.*D::B.*T001|D::B.*D::A.*T001/, 'duplicate code names both' );

my $bad = $tmp->child('bad');
$bad->mkpath;
rule_file( $bad, 'B::Bad', 's1' );
like( dies { Puff::Rules->load( rule_paths => ["$bad"] ) }, qr/B::Bad.*invalid code 's1'/, 'bad code dies' );

my $res = $tmp->child('res');
$res->mkpath;
rule_file( $res, 'B::Res', 'P001' );
like( dies { Puff::Rules->load( rule_paths => ["$res"] ) }, qr/B::Res.*P001.*reserved/, 'P001 reserved' );

# Module::Pluggable discovery
my $lib = $tmp->child('lib');
$lib->child(qw( Puff Rule Fake ))->mkpath;
$lib->child(qw( Puff Rule Fake Found.pm ))->spew_utf8(<<'PM');
package Puff::Rule::Fake::Found;
use v5.36;
use parent 'Puff::Rule';
sub code {'Q001'}
1;
PM
$lib->child(qw( Puff Rule Fake NotARule.pm ))->spew_utf8("package Puff::Rule::Fake::NotARule;\n1;\n");
unshift @INC, "$lib";
is( [ grep {/\AQ/} map { $_->code } Puff::Rules->load( rule_paths => [] ) ], ['Q001'], 'pluggable discovery' );

like( dies { Puff::Rules->load( rule_paths => ["$tmp/nope"] ) }, qr/not a directory/, 'missing rule path' );

done_testing;
