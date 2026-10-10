use v5.36;
use Test2::V0;

use lib 't/lib';
use TestCommand qw( run_capture );

use Cwd        qw( getcwd );
use Path::Tiny qw( path tempdir );

use Puff::Engine ();
use Puff::Rules  ();
use Puff::Source ();
use Puff::Test   qw( run_corpus );

run_corpus('B010');

my @classes = Puff::Rules->load;
my %class   = map { $_->code => $_ } @classes;

sub violations ( $text, @codes ) {
    my $result = Puff::Engine->new( rules => [ map { $class{$_}->new } @codes ] )
        ->process_source( Puff::Source->from_string($text), file => 'x.pl' );
    return $result->{violations};
}

is(
    [ map { $_->message } @{ violations( "chmod 755, \$f;\n", 'B010' ) } ],
    ['chmod mode 755 is decimal (octal 01363); write 0755'],
    'chmod message'
);
is(
    [ map { $_->message } @{ violations( "umask 22;\n", 'B010' ) } ],
    ['umask mask 22 is decimal (octal 026); write 022'],
    'two-digit umask message'
);
is(
    [ map { $_->message } @{ violations( "\$p->mkdir( { mode => 711 } );\n", 'B010' ) } ],
    ['->mkdir mode 711 is decimal (octal 01307); write 0711'],
    'method option message'
);
is( $class{B010}->fix_safety, 'unsafe', 'fix is unsafe' );

is(
    [ map { $_->message } @{ violations( "chmod 1777, \$d;\n", 'B010' ) } ],
    ['chmod mode 1777 is decimal (octal 03361); write 01777'],
    'four-digit message'
);
is(
    [ map { $_->message } @{ violations( "mkdir 'x', 511;\nchmod 493, \$f;\numask 18;\n", 'B010' ) } ],
    [],
    'decimal values of common modes are taken as deliberate'
);

# With S009: a decimal mode is reported by B010 for the missing zero, and by
# S009 when either its real value (chmod 755 is 01363) or its intended octal
# reading (chmod 777 as 0777) is world-writable. The fixed octal mode is
# reported only by S009, and never by B003.
my $text = "chmod 777, \$d;\numask 20;\nchmod 755, \$f;\nchmod 644, \$f;\n";
is(
    [ map { [ $_->code, $_->line ] } @{ violations( $text, qw( B003 B010 S009 ) ) } ],
    [ [ 'S009', 1 ], [ 'B010', 1 ], [ 'S009', 2 ], [ 'B010', 2 ], [ 'S009', 3 ], [ 'B010', 3 ], [ 'B010', 4 ] ],
    'decimal modes: B010 for the base, S009 for a real or intended world-writable mode'
);
my $fixed = "chmod 0777, \$d;\numask 020;\nchmod 0755, \$f;\nchmod 0644, \$f;\n";
is(
    [ map { [ $_->code, $_->line ] } @{ violations( $fixed, qw( B003 B010 S009 ) ) } ],
    [ [ 'S009', 1 ], [ 'S009', 2 ] ],
    'fixed modes: S009 still reports, B003 and B010 do not'
);

sub selected (@select) {
    return [ grep { $_ eq 'B010' } map { $_->code } Puff::Rules->instantiate( \@classes, select => [@select] ) ];
}
is( selected( 'S', 'B' ), [], 'not selected by the default prefixes' );
is( selected('B01'), [], 'not selected by a longer prefix' );
is( selected('B010'), ['B010'], 'selected by its exact code' );
is( selected('ALL'), ['B010'], 'selected by ALL' );

# Through the CLI: the prefix B does not enable the rule, its code does, and
# fixing the whole file with every rule is stable.
my $root = path(getcwd)->absolute;
my @puff = (
    $^X, '-I' . $root->child('lib'), '-I' . $root->child( 'local', 'lib', 'perl5' ),
    $root->child( 'bin', 'puff' )->stringify, 'check', '--no-config',
);
my $dir  = tempdir();
my $file = $dir->child('x.pl');
$file->spew_utf8("my \$f;\nchmod 755, \$f;\nmkdir \$f, 777;\numask 77;\nchmod 777, \$f;\nchmod 0777, \$f;\n");
my $out = run_capture( undef, @puff, '--select', 'B', "$file" );
unlike( $out, qr/B010/, '--select B does not enable B010' );
$out = run_capture( undef, @puff, '--select', 'B010', "$file" );
like( $out, qr/:2:7: B010 chmod mode 755 is decimal/, '--select B010 enables it' );
is( $? >> 8, 1, 'and exits 1' );

run_capture( undef, @puff, '--select', 'ALL', '--fix', '--unsafe-fixes', "$file" );
my $once = $file->slurp_utf8;
like(
    $once,
    qr/chmod 0755, \$f;\nmkdir \$f, 0777;\numask 077;\nchmod 0777, \$f;\nchmod 0777, \$f;/,
    'fixed with every rule selected'
);
run_capture( undef, @puff, '--select', 'ALL', '--fix', '--unsafe-fixes', "$file" );
is( $file->slurp_utf8, $once, 'a second fix run changes nothing' );

done_testing;
