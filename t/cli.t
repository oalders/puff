use v5.36;
use Test2::V0;

use Cwd        qw( getcwd );
use JSON::PP   ();
use Path::Tiny qw( path tempdir );

my $root = path(getcwd)->absolute;
my @PERL = ( $^X, '-I' . $root->child('lib'), '-I' . $root->child( 'local', 'lib', 'perl5' ) );
my $PUFF = $root->child( 'bin', 'puff' )->stringify;

# Runs bin/puff in $dir. Returns (stdout, stderr, exit code).
sub puff ( $dir, @args ) {
    my $err  = path( $dir, '..', 'stderr.txt' );
    my $cmd  = join ' ', map { quotemeta } @PERL, $PUFF, @args;
    my $orig = getcwd;
    chdir $dir or die "chdir $dir: $!";
    my $out = qx{$cmd 2>"$err"};
    my $exit = $? >> 8;
    chdir $orig or die "chdir $orig: $!";
    return ( $out, $err->slurp_utf8, $exit );
}

sub corpus ($name) { $root->child( 't', 'corpus', $name ) }

# A fresh project dir holding copies of corpus files (name => corpus path).
sub project (%files) {
    my $base = tempdir();
    my $dir  = $base->child('project');
    $dir->mkpath;
    for my $name ( sort keys %files ) {
        my $dest = $dir->child($name);
        $dest->parent->mkpath;
        corpus( $files{$name} )->copy($dest);
    }
    return ( $base, $dir );
}

my %FILES = (
    'rand.pl'          => 'S001/basic.pl',
    'lib/two_arg.pl'   => 'S002/fixed.pl',
    'bin/bareword.pl'  => 'S003/basic.pl',
    'lib/declined.pl'  => 'S002/declined.pl',
);

subtest 'check lints and exits 1' => sub {
    my ( $keep, $dir ) = project(%FILES);
    my ( $out, $err, $exit ) = puff( $dir, 'check' );
    is( $exit, 1, 'exit 1' );
    is( $err,  '', 'nothing on STDERR' );
    like( $out, qr{^rand\.pl:4:9: S001 \S.* \[\*\*\]$}m,        'S001 line with unsafe-fix marker' );
    like( $out, qr{^lib/two_arg\.pl:5:1: S002 Use three-argument open \[\*\*\]$}m, 'S002 line' );
    like( $out, qr{^bin/bareword\.pl:5:1: S003 \S.* \[\*\*\]$}m,  'S003 line' );
    like( $out, qr{^Found \d+ violations\.$}m,                    'summary' );
    like( $out, qr{^\d+ more fixable with --unsafe-fixes$}m,      'unsafe fixes mentioned' );
    unlike( $out, qr{fixable with --fix}, 'no safe fixes available' );

    my @lines = grep { /^\S+:\d+:\d+: / } split /\n/, $out;
    my @sorted = sort {
        my @x = split /:/, $a;
        my @y = split /:/, $b;
        $x[0] cmp $y[0] || $x[1] <=> $y[1] || $x[2] <=> $y[2]
    } @lines;
    is( \@lines, \@sorted, 'sorted by file, line and column' );
};

subtest 'check --fix applies only safe fixes' => sub {
    my ( $keep, $dir ) = project(%FILES);
    my %before = map { $_ => $dir->child($_)->slurp_raw } keys %FILES;
    my ( $out, $err, $exit ) = puff( $dir, 'check', '--fix' );
    is( $exit, 1, 'exit 1' );
    is( { map { $_ => $dir->child($_)->slurp_raw } keys %FILES }, \%before, 'files unchanged' );
    like( $out, qr{^\d+ more fixable with --unsafe-fixes$}m, 'mentions --unsafe-fixes' );
    like( $out, qr{^Fixed 0 violations in 0 files\.$}m,      'fixed count' );
};

subtest 'check --diff --unsafe-fixes prints a diff and writes nothing' => sub {
    my ( $keep, $dir ) = project(%FILES);
    my %before = map { $_ => $dir->child($_)->slurp_raw } keys %FILES;
    for my $args ( [ '--diff', '--unsafe-fixes' ], [ '--diff', '--fix', '--unsafe-fixes' ] ) {
        my ( $out, $err, $exit ) = puff( $dir, 'check', @$args );
        is( $exit, 1, "exit 1 (@$args)" );
        like( $out, qr{^--- a/rand\.pl$}m,    '--- header' );
        like( $out, qr{^\+\+\+ b/rand\.pl$}m, '+++ header' );
        like( $out, qr{^@@ }m,                'hunk header' );
        like( $out, qr{^\+use Math::Random::Secure}m, 'added line' );
        like( $err, qr{^Would fix \d+ violations in 4 files\.$}m, 'summary on STDERR' );
        is( { map { $_ => $dir->child($_)->slurp_raw } keys %FILES }, \%before, 'files unchanged' );
    }
};

subtest 'check --diff with nothing to fix exits 0' => sub {
    my ( $keep, $dir ) = project( 'clean.pl' => 'S002/not-reported.pl' );
    my ( $out, $err, $exit ) = puff( $dir, 'check', '--diff', '--unsafe-fixes', '--select', 'S002' );
    is( $out,  '', 'no diff' );
    is( $exit, 0,  'exit 0' );
};

subtest 'check --fix --unsafe-fixes rewrites files' => sub {
    my %fixable = (
        'rand.pl'         => 'S001/basic.pl',
        'bin/bareword.pl' => 'S003/basic.pl',
        'lib/two_arg.pl'  => 'S002/fixed.pl',
    );
    my ( $keep, $dir ) = project(%fixable);
    my $mode = ( stat $dir->child('rand.pl') )[2] & 07777;
    my ( $out, $err, $exit ) = puff( $dir, 'check', '--fix', '--unsafe-fixes', '--select', 'S001,S002', '--extend-select', 'S003' );
    is( $err, '', 'nothing on STDERR' );
    like( $out, qr{^Fixed \d+ violations in 3 files\.$}m, 'fixed summary' );
    for my $name (qw( rand.pl bin/bareword.pl )) {
        is( $dir->child($name)->slurp_raw, corpus( $fixable{$name} =~ s/\.pl\z/.fixed.pl/r )->slurp_raw,
            "$name matches .fixed.pl" );
    }
    is( ( stat $dir->child('rand.pl') )[2] & 07777, $mode, 'mode kept' );

    ( $out, $err, $exit ) = puff( $dir, 'check', 'rand.pl', 'bin' );
    is( $exit, 0, 'second check of the fully fixed files exits 0' ) or diag $out, $err;
    like( $out, qr{^Found 0 violations\.$}m, 'no violations' );

    # S002's corpus still has bareword handles (S003), so fix it with S002 alone.
    ( $keep, $dir ) = project( 'lib/two_arg.pl' => 'S002/fixed.pl' );
    ( $out, $err, $exit ) = puff( $dir, 'check', '--fix', '--unsafe-fixes', '--select', 'S002' );
    is( $exit, 0, 'S002-only fix leaves no S002 violations' ) or diag $out, $err;
    is( $dir->child('lib/two_arg.pl')->slurp_raw, corpus('S002/fixed.fixed.pl')->slurp_raw,
        'lib/two_arg.pl matches .fixed.pl' );
};

subtest 'check --fix that fixes everything exits 0' => sub {
    my ( $keep, $dir ) = project( 'rand.pl' => 'S001/basic.pl' );
    my ( $out, $err, $exit ) = puff( $dir, 'check', '--fix', '--unsafe-fixes' );
    is( $exit, 0, 'exit 0' );
    like( $out, qr{^Fixed 2 violations in 1 file\.$}m, 'singular file' );
};

subtest 'unsafe-fixes in config' => sub {
    my ( $keep, $dir ) = project( 'rand.pl' => 'S001/basic.pl' );
    $dir->child('.puff.toml')->spew_utf8("unsafe-fixes = true\n");
    my ( $out, $err, $exit ) = puff( $dir, 'check' );
    like( $out, qr{^rand\.pl:4:9: S001 .* \[\*\]$}m, 'marked as fixable with current settings' );
    like( $out, qr{^2 fixable with --fix$}m,          'fixable with --fix' );
    ( $out, $err, $exit ) = puff( $dir, 'check', '--fix' );
    is( $exit, 0, '--fix applies unsafe fixes' );
    is( $dir->child('rand.pl')->slurp_raw, corpus('S001/basic.fixed.pl')->slurp_raw, 'fixed' );
};

subtest 'check --select S002 --output-format json' => sub {
    my ( $keep, $dir ) = project(%FILES);
    my ( $out, $err, $exit ) = puff( $dir, 'check', '--select', 'S002', '--output-format', 'json' );
    is( $exit, 1, 'exit 1' );
    my $data = JSON::PP->new->decode($out);
    ok( scalar @$data, 'has violations' );
    is( [ grep { $_->{code} ne 'S002' } @$data ], [], 'only S002' );
    is(
        $data->[0],
        {
            code    => 'S002',
            message => 'Use three-argument open',
            file    => 'lib/declined.pl',
            line    => match qr/\A\d+\z/,
            column  => match qr/\A\d+\z/,
            fix     => { safety => 'unsafe', available => bool(0), applied => bool(0) },
        },
        'violation structure (a declined fix is not available)'
    );
    ok( ( grep { $_->{fix}{available} } @$data ), 'fixable violations are available' );
};

subtest 'rules and rule' => sub {
    my ( $keep, $dir ) = project();
    my ( $out, $err, $exit ) = puff( $dir, 'rules' );
    is( $exit, 0, 'rules exits 0' );
    like( $out, qr{^S001\s+unsafe\s+\S}m, 'S001' );
    like( $out, qr{^S002\s+unsafe\s+Use three-argument open$}m, 'S002' );
    like( $out, qr{^S003\s+unsafe\s+\S}m, 'S003' );
    like( $out, qr{^P001\s+none\s+suppression comment must list codes$}m, 'P001' );

    ( $out, $err, $exit ) = puff( $dir, 'rule', 'S002' );
    is( $exit, 0, 'rule exits 0' );
    like( $out, qr{\AS002: Use three-argument open\n}, 'code and summary' );
    like( $out, qr{^Fix safety: unsafe$}m,             'fix safety' );
    like( $out, qr{^Two-argument open takes the mode}m, 'explanation' );

    ( $out, $err, $exit ) = puff( $dir, 'rule', 'P001' );
    is( $exit, 0, 'rule P001 exits 0' );
    like( $out, qr{\AP001: suppression comment must list codes\n}, 'P001 summary' );

    ( $out, $err, $exit ) = puff( $dir, 'rule', 'X999' );
    is( $exit, 2, 'unknown rule exits 2' );
    like( $err, qr/Unknown rule X999/, 'error on STDERR' );

    ( $out, $err, $exit ) = puff( $dir, 'rule' );
    is( $exit, 2, 'missing code exits 2' );
};

subtest 'config file' => sub {
    my ( $keep, $dir ) = project( 'rand.pl' => 'S001/basic.pl' );
    $dir->child('.puff.toml')->spew_utf8(qq{ignore = ["S001"]\n});
    my ( $out, $err, $exit ) = puff( $dir, 'check' );
    is( $exit, 0, 'ignore is honoured' );
    unlike( $out, qr/S001/, 'no S001' );

    ( $out, $err, $exit ) = puff( $dir, 'check', '--no-config' );
    is( $exit, 1, '--no-config ignores it' );
    like( $out, qr/S001/, 'S001 reported' );

    my $other = $dir->parent->child('other.toml');
    $other->spew_utf8(qq{select = ["S002"]\n});
    ( $out, $err, $exit ) = puff( $dir, 'check', '--config', "$other" );
    is( $exit, 0, '--config reads the given file' );

    $dir->child('.puff.toml')->spew_utf8(qq{ignroe = ["S001"]\n});
    ( $out, $err, $exit ) = puff( $dir, 'check' );
    is( $exit, 2, 'unknown key exits 2' );
    like( $err, qr/Unknown key 'ignroe'/, 'error names the key' );
    is( $out, '', 'nothing on STDOUT' );
};

subtest 'exclude' => sub {
    my ( $keep, $dir ) = project(
        'local/lib/Rand.pm' => 'S001/basic.pl',
        't/local/x.t'       => 'S001/basic.pl',
        'vendor/x.pl'       => 'S001/basic.pl',
        'lib/ok.pm'         => 'S002/not-reported.pl',
        'lib/notes.txt'     => 'S001/basic.pl',
    );
    my ( $out, $err, $exit ) = puff( $dir, 'check', '--select', 'S001' );
    is( $exit, 1, 'vendor/x.pl still checked' );
    like( $out,   qr{^vendor/x\.pl:}m, 'vendor reported' );
    unlike( $out, qr{^local/}m,        'local/ skipped' );
    like( $out,   qr{^t/local/x\.t:}m,  't/local/ checked: default excludes are anchored to the root' );
    unlike( $out, qr{notes\.txt},      'non-Perl file skipped' );

    ( $out, $err, $exit ) = puff( $dir, 'check', '--select', 'S001', './local', 't' );
    unlike( $out, qr{lib/Rand\.pm},    'files under a named ./local are still skipped' );
    like( $out,   qr{^t/local/x\.t:}m, 'searching t/ checks t/local' );

    $dir->child('.puff.toml')->spew_utf8('');
    ( $out, $err, $exit ) = puff( $dir->child('t'), 'check', '--select', 'S001', '--config', '../.puff.toml' );
    like( $out, qr{^local/x\.t:}m, 'root is the config dir: t/local is checked from inside t/' ) or diag $err;

    $dir->child('.puff.toml')->spew_utf8(qq{exclude = ["vendor/x.pl", "/t"]\n});
    ( $out, $err, $exit ) = puff( $dir, 'check', '--select', 'S001' );
    is( $exit, 0, 'config exclude adds to the defaults; /t is anchored' ) or diag $out;

    ( $out, $err, $exit ) = puff( $dir, 'check', '--select', 'S001', 'lib/notes.txt' );
    is( $exit, 1, 'a file named explicitly is checked whatever its name' );
};

subtest 'errors exit 2' => sub {
    my ( $keep, $dir ) = project( 'rand.pl' => 'S001/basic.pl' );
    my ( $out, $err, $exit ) = puff( $dir, 'check', 'missing.pl' );
    is( $exit, 2, 'missing path exits 2' );
    like( $err, qr/missing\.pl/, 'names the path' );

    my $unreadable = $dir->child('unreadable.pl');
    $unreadable->spew_utf8("1;\n");
    chmod 0, "$unreadable";
    if ( !-r $unreadable ) {
        ( $out, $err, $exit ) = puff( $dir, 'check', 'unreadable.pl' );
        is( $exit, 2, 'unreadable file exits 2' );
        like( $err, qr/^unreadable\.pl: error: Cannot read unreadable\.pl: .*Permission denied$/m,
            'read error without an internal source location' );
    }
    chmod 0644, "$unreadable";
    $unreadable->remove;

    ( $out, $err, $exit ) = puff( $dir, 'check', 'missing.pl', 'rand.pl' );
    is( $exit, 2, '2 takes priority over 1' );
    like( $out, qr/^rand\.pl:4:9: S001/m, 'other files still processed' );

    ( $out, $err, $exit ) = puff( $dir, 'check', '--output-format', 'xml' );
    is( $exit, 2, 'bad output format exits 2' );

    ( $out, $err, $exit ) = puff( $dir, 'check', '--bogus' );
    is( $exit, 2, 'unknown option exits 2' );

    ( $out, $err, $exit ) = puff( $dir, 'frobnicate' );
    is( $exit, 2, 'unknown command exits 2' );
    is( $out,  '', 'nothing on STDOUT' );
    like( $err, qr/^Unrecognized command: frobnicate$/m, 'error on STDERR' );

    ( $out, $err, $exit ) = puff( $dir, 'check', '--select', 'S999' );
    is( $exit, 2, 'selecting an unknown rule exits 2' );
    like( $err, qr/^Unknown rule selector: S999$/m, 'and says so' );
};

subtest 'CRLF files are linted but not fixed' => sub {
    my ( $keep, $dir ) = project();
    my $file = $dir->child('crlf.pl');
    $file->spew_raw( corpus('S001/basic.pl')->slurp_raw =~ s/\n/\r\n/gr );
    my $before = $file->slurp_raw;
    my ( $out, $err, $exit ) = puff( $dir, 'check', '--fix', '--unsafe-fixes' );
    is( $exit, 1, 'violations remain' );
    is( $file->slurp_raw, $before, 'file unchanged' );
    like( $err, qr/^crlf\.pl: CR or CRLF line endings: fixes not applied$/m, 'reported' );
    unlike( $out, qr/\[\*\*?\]|fixable/, 'no fix offered' );
};

done_testing;
