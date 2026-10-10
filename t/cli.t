use v5.36;
use Test2::V0;

use lib 't/lib';
use TestCommand qw( run_capture );

use Cwd        qw( getcwd );
use Encode     ();
use JSON::PP   ();
use Path::Tiny qw( path tempdir );
use Puff::Path qw( display_name );

my $root = path(getcwd)->absolute;
my @PERL = ( $^X, '-I' . $root->child('lib'), '-I' . $root->child( 'local', 'lib', 'perl5' ) );
my $PUFF = $root->child( 'bin', 'puff' )->stringify;

# Runs bin/puff in $dir. Returns (stdout, stderr, exit code), all as bytes.
# @$perl_args (such as -e code that loads bin/puff) are passed to perl in
# place of bin/puff.
sub puff_raw_with ( $dir, $perl_args, @args ) {
    my $err  = path( $dir, '..', 'stderr.txt' );
    my $orig = getcwd;
    chdir $dir or die "chdir $dir: $!";
    my $out  = run_capture( $err, @PERL, ( @$perl_args ? @$perl_args : $PUFF ), @args );
    my $exit = $? >> 8;
    chdir $orig or die "chdir $orig: $!";
    return ( $out, $err->slurp_raw, $exit );
}

sub puff_raw ( $dir, @args ) { puff_raw_with( $dir, [], @args ) }

# Like puff_raw_with, but STDERR is decoded.
sub puff_with ( $dir, $perl_args, @args ) {
    my ( $out, $err, $exit ) = puff_raw_with( $dir, $perl_args, @args );
    return ( $out, Encode::decode( 'UTF-8', $err ), $exit );
}

sub puff ( $dir, @args ) { puff_with( $dir, [], @args ) }

sub corpus ($name) { $root->child( 't', 'corpus', $name ) }

# A fresh project dir holding copies of corpus files (name => corpus path).
# Temporary directories live until the test ends.
my @TEMPDIRS;

sub project (%files) {
    my $base = tempdir();
    my $dir  = $base->child('project');
    $dir->mkpath;
    for my $name ( sort keys %files ) {
        my $dest = $dir->child($name);
        $dest->parent->mkpath;
        corpus( $files{$name} )->copy($dest);
    }
    push @TEMPDIRS, $base;
    return $dir;
}

my %FILES = (
    'rand.pl'         => 'S001/basic.pl',
    'lib/two_arg.pl'  => 'S002/fixed.pl',
    'bin/bareword.pl' => 'S003/basic.pl',
    'lib/declined.pl' => 'S002/declined.pl',
);

subtest 'check lints and exits 1' => sub {
    my $dir = project(%FILES);
    my ( $out, $err, $exit ) = puff( $dir, 'check' );
    is( $exit, 1, 'exit 1' );
    is( $err, '', 'nothing on STDERR' );
    like( $out, qr{^rand\.pl:4:7: S001 \S.* \[\*\*\]$}m, 'S001 line with unsafe-fix marker' );
    like( $out, qr{^lib/two_arg\.pl:5:1: S002 Use three-argument open \[\*\*\]$}m, 'S002 line' );
    like( $out, qr{^bin/bareword\.pl:5:1: S003 \S.* \[\*\*\]$}m, 'S003 line' );
    like( $out, qr{^Found \d+ violations \(checked 4 files\)\.$}m, 'summary counts the files' );
    like( $out, qr{^\d+ more fixable with --unsafe-fixes$}m, 'unsafe fixes mentioned' );
    unlike( $out, qr{fixable with --fix}, 'no safe fixes available' );

    my @lines  = grep {/^\S+:\d+:\d+: /} split /\n/, $out;
    my @sorted = sort {
        my @x = split /:/, $a;
        my @y = split /:/, $b;
        $x[0] cmp $y[0] || $x[1] <=> $y[1] || $x[2] <=> $y[2]
    } @lines;
    is( \@lines, \@sorted, 'sorted by file, line and column' );
};

subtest 'check --fix applies only safe fixes' => sub {
    my $dir    = project(%FILES);
    my %before = map { $_ => $dir->child($_)->slurp_raw } keys %FILES;
    my ( $out, undef, $exit ) = puff( $dir, 'check', '--fix' );
    is( $exit, 1, 'exit 1' );
    is( { map { $_ => $dir->child($_)->slurp_raw } keys %FILES }, \%before, 'files unchanged' );
    like( $out, qr{^\d+ more fixable with --unsafe-fixes$}m, 'mentions --unsafe-fixes' );
    like( $out, qr{^Fixed 0 violations in 0 files\.$}m, 'fixed count' );
};

subtest 'check --diff --unsafe-fixes prints a diff and writes nothing' => sub {
    my $dir    = project(%FILES);
    my %before = map { $_ => $dir->child($_)->slurp_raw } keys %FILES;
    for my $args ( [ '--diff', '--unsafe-fixes' ], [ '--diff', '--fix', '--unsafe-fixes' ] ) {
        my ( $out, $err, $exit ) = puff( $dir, 'check', @$args );
        is( $exit, 1, "exit 1 (@$args)" );
        like( $out, qr{^--- a/rand\.pl$}m, '--- header' );
        like( $out, qr{^\+\+\+ b/rand\.pl$}m, '+++ header' );
        like( $out, qr{^@@ }m, 'hunk header' );
        like( $out, qr{^\+use Crypt::PRNG qw\(rand\);$}m, 'added line' );
        like( $err, qr{^Would fix \d+ violations in 4 files\.$}m, 'summary on STDERR' );
        is( { map { $_ => $dir->child($_)->slurp_raw } keys %FILES }, \%before, 'files unchanged' );
    }
};

subtest 'check --diff with nothing to fix exits 0' => sub {
    my $dir = project( 'clean.pl' => 'S002/not-reported.pl' );
    my ( $out, undef, $exit ) = puff( $dir, 'check', '--diff', '--unsafe-fixes', '--select', 'S002' );
    is( $out, '', 'no diff' );
    is( $exit, 0, 'exit 0' );
};

subtest 'check --fix --unsafe-fixes rewrites files' => sub {
    my %fixable = (
        'rand.pl'         => 'S001/basic.pl',
        'bin/bareword.pl' => 'S003/basic.pl',
        'lib/two_arg.pl'  => 'S002/fixed.pl',
    );
    my $dir  = project(%fixable);
    my $mode = ( stat $dir->child('rand.pl') )[2] & 07777;
    my ( $out, $err, $exit )
        = puff( $dir, 'check', '--fix', '--unsafe-fixes', '--select', 'S001,S002', '--extend-select', 'S003' );
    is( $err, '', 'nothing on STDERR' );
    like( $out, qr{^Fixed \d+ violations in 3 files\.$}m, 'fixed summary' );
    for my $name (qw( rand.pl bin/bareword.pl )) {
        is(
            $dir->child($name)->slurp_raw, corpus( $fixable{$name} =~ s/\.pl\z/.fixed.pl/r )->slurp_raw,
            "$name matches .fixed.pl"
        );
    }
    is( ( stat $dir->child('rand.pl') )[2] & 07777, $mode, 'mode kept' );

    ( $out, $err, $exit ) = puff( $dir, 'check', 'rand.pl', 'bin' );
    is( $exit, 0, 'second check of the fully fixed files exits 0' ) or diag $out, $err;
    like( $out, qr{^Found 0 violations \(checked 2 files\)\.$}m, 'no violations' );

    # S002's corpus still has bareword handles (S003), so fix it with S002 alone.
    $dir = project( 'lib/two_arg.pl' => 'S002/fixed.pl' );
    ( $out, $err, $exit ) = puff( $dir, 'check', '--fix', '--unsafe-fixes', '--select', 'S002' );
    is( $exit, 0, 'S002-only fix leaves no S002 violations' ) or diag $out, $err;
    is(
        $dir->child('lib/two_arg.pl')->slurp_raw, corpus('S002/fixed.fixed.pl')->slurp_raw,
        'lib/two_arg.pl matches .fixed.pl'
    );
};

subtest 'check --fix that fixes everything exits 0' => sub {
    my $dir = project( 'rand.pl' => 'S001/basic.pl' );
    my ( $out, undef, $exit ) = puff( $dir, 'check', '--fix', '--unsafe-fixes' );
    is( $exit, 0, 'exit 0' );
    like( $out, qr{^Fixed 2 violations in 1 file\.$}m, 'singular file' );
};

subtest 'unsafe-fixes in config' => sub {
    my $dir = project( 'rand.pl' => 'S001/basic.pl' );
    $dir->child('.puff.toml')->spew_utf8("unsafe-fixes = true\n");
    my ( $out, $err, $exit ) = puff( $dir, 'check' );
    like( $out, qr{^rand\.pl:4:7: S001 .* \[\*\]$}m, 'marked as fixable with current settings' );
    like( $out, qr{^2 fixable with --fix$}m, 'fixable with --fix' );
    ( $out, $err, $exit ) = puff( $dir, 'check', '--fix' );
    is( $exit, 0, '--fix applies unsafe fixes' );
    is( $dir->child('rand.pl')->slurp_raw, corpus('S001/basic.fixed.pl')->slurp_raw, 'fixed' );
};

subtest 'check --select S002 --output-format json' => sub {
    my $dir = project(%FILES);
    my ( $out, undef, $exit ) = puff( $dir, 'check', '--select', 'S002', '--output-format', 'json' );
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

# Decodes JSON Lines output, one object per line; fails if any line is not JSON.
sub jsonl ($out) {
    my @lines = split /\n/, $out;
    my @events;
    for my $line (@lines) {
        my $event = eval { JSON::PP->new->decode($line) };
        ok( $event, 'line is JSON on its own' ) or diag $line;
        push @events, $event if $event;
    }
    return @events;
}

subtest 'check --output-format jsonl' => sub {
    my $dir = project(%FILES);
    my ( $out, $err, $exit ) = puff( $dir, 'check', '--output-format', 'jsonl', 'missing.pl', '.' );
    is( $exit, 2, 'exit 2 for a missing file' );
    is( $err, q{}, 'nothing on STDERR, not even the missing file' );
    my @events = jsonl($out);
    is( [ map { $_->{type} } @events ], [ 'start', ('file') x 5, 'done' ], 'start, a file event per file, done' );
    is( $events[0], { type => 'start', total => 5 }, 'start has the total' );
    is( $events[-1], { type => 'done', exit_code => 2 }, 'done has the exit code' );
    my @files = @events[ 1 .. $#events - 1 ];
    is(
        [ map { $_->{file} } @files ], [qw( missing.pl rand.pl bin/bareword.pl lib/declined.pl lib/two_arg.pl )],
        'in processing order, not sorted'
    );
    is(
        $files[0],
        {
            type          => 'file', file      => 'missing.pl', error => 'No such file or directory', fixed => 0,
            fixes_skipped => undef, violations => []
        },
        'missing file has its error'
    );
    ok( !exists $files[1]{diff}, 'no diff key outside --diff' );
    is( [ grep { defined $_->{error} } @files[ 1 .. 4 ] ], [], 'no errors for files that exist' );
    my ($rand) = grep { $_->{file} eq 'rand.pl' } @files;
    is(
        $rand->{violations}[0],
        {
            code    => 'S001',
            message => match qr/\S/,
            file    => 'rand.pl',
            line    => 4,
            column  => 7,
            fix     => { safety => 'unsafe', available => bool(1), applied => bool(0) },
        },
        'violations have the json reporter shape'
    );

    ( $out, $err, $exit ) = puff( $dir, 'check', '--output-format', 'jsonl', '--select', 'S001', 'rand.pl' );
    @events = jsonl($out);
    is( $exit, 1, 'exit 1 with violations' );
    is( $events[-1], { type => 'done', exit_code => 1 }, 'done says 1' );

    ( $out, $err, $exit ) = puff( $dir, 'check', '--output-format', 'jsonl', '--select', 'S002', 'rand.pl' );
    @events = jsonl($out);
    is( $exit, 0, 'exit 0 when clean' );
    is( $events[-1], { type => 'done', exit_code => 0 }, 'done says 0' );
    is( $events[1]{violations}, [], 'no violations' );
};

subtest 'check --output-format jsonl --diff' => sub {
    my $dir    = project( 'rand.pl' => 'S001/basic.pl', 'clean.pl' => 'S002/not-reported.pl' );
    my %before = map { $_ => $dir->child($_)->slurp_raw } qw( rand.pl clean.pl );
    my ( $out, $err, $exit )
        = puff( $dir, 'check', '--output-format', 'jsonl', '--diff', '--unsafe-fixes', '--select', 'S001,S002' );
    is( $exit, 1, 'exit 1: the diff would change something' );
    is( $err, q{}, 'no summary on STDERR' );
    my @lines = split /\n/, $out;
    is( scalar( grep { !/\A\{.*\}\z/ } @lines ), 0, 'no plain diff text outside JSON lines' );
    my @events = jsonl($out);
    my %file   = map { $_->{file} => $_ } grep { $_->{type} eq 'file' } @events;
    like( $file{'rand.pl'}{diff}, qr{^\+use Crypt::PRNG qw\(rand\);$}m, 'fixable file has its diff' );
    ok( exists $file{'clean.pl'}{diff}, 'clean file has a diff key' );
    is( $file{'clean.pl'}{diff}, undef, '... which is null' );
    is( $file{'rand.pl'}{fixed}, 0, 'nothing written' );
    is( $events[-1], { type => 'done', exit_code => 1 }, 'done' );
    is( { map { $_ => $dir->child($_)->slurp_raw } qw( rand.pl clean.pl ) }, \%before, 'files unchanged' );
};

subtest 'check --output-format jsonl --fix' => sub {
    my $dir = project( 'two_arg.pl' => 'S002/fixed.pl' );
    my ( $out, $err, $exit )
        = puff( $dir, 'check', '--output-format', 'jsonl', '--fix', '--unsafe-fixes', '--select', 'S002,S003' );
    is( $exit, 1, 'exit 1: violations remain' ) or diag $err;
    my @events = jsonl($out);
    my ($file) = grep { $_->{type} eq 'file' } @events;
    ok( $file->{fixed} > 0, 'fixed counts the fixes written' );
    ok( scalar @{ $file->{violations} }, 'remaining violations listed' );
    is( [ grep { $_->{fix}{applied} } @{ $file->{violations} } ], [], 'none marked applied' );
    is( $events[-1], { type => 'done', exit_code => 1 }, 'done' );
};

subtest 'check --output-format jsonl: CRLF fixes_skipped' => sub {
    my $dir = project( 'rand.pl' => 'S001/basic.pl' );
    $dir->child('crlf.pl')->spew_raw( corpus('S001/basic.pl')->slurp_raw =~ s/\n/\r\n/gr );
    my ( $out, $err, $exit )
        = puff( $dir, 'check', '--output-format', 'jsonl', '--fix', '--unsafe-fixes', '--select', 'S001' );
    is( $exit, 1, 'violations remain in the CRLF file' );
    is( $err, q{}, 'fixes_skipped is not printed to STDERR' );
    my %file = map { $_->{file} => $_ } grep { $_->{type} eq 'file' } jsonl($out);
    is(
        $file{'crlf.pl'}{fixes_skipped}, 'CR or CRLF line endings: fixes not applied',
        'CRLF file event has fixes_skipped'
    );
    ok( exists $file{'rand.pl'}{fixes_skipped}, 'other file event has fixes_skipped' );
    is( $file{'rand.pl'}{fixes_skipped}, undef, '... which is null' );
};

subtest 'check --output-format jsonl: one line per event' => sub {
    my $dir   = project();
    my @names = ( 'q"uote{"type":"done","exit_code":0}.pl', "new\nline.pl" );
    my @made  = grep {
        eval { corpus('S001/basic.pl')->copy( $dir->child($_) ); 1 }
    } @names;
    ok( scalar @made, 'made files with awkward names' );
    my ( $out, $err, $exit ) = puff( $dir, 'check', '--output-format', 'jsonl', '--select', 'S001' );
    is( $exit, 1, 'exit 1' ) or diag $err;
    my @lines  = split /\n/, $out;
    my @events = jsonl($out);
    is( scalar @lines, scalar @events, 'every line is one event' );
    is( scalar @events, @made + 2, 'start, a file event per file, done' );
    is(
        [ sort map { $_->{file} } grep { $_->{type} eq 'file' } @events ], [ sort map { display_name($_) } @made ],
        q{names come back as shown: control characters escaped}
    );
    is( $events[-1], { type => 'done', exit_code => 1 }, 'the real done is last' );
};

subtest 'check --output-format jsonl: non-ASCII' => sub {
    my $dir = project();
    $dir->child('cafe.pl')->spew_utf8("use utf8;\nmy \$x = new Caf\x{e9}(1);\nprint \$x;\n");
    my ( $out, $err, $exit ) = puff( $dir, 'check', '--output-format', 'jsonl', '--select', 'B004' );
    is( $exit, 1, 'exit 1' ) or diag $err;
    my @lines = split /\n/, $out;
    is( [ grep { !/\A[\x00-\x7f]*\z/ } @lines ], [], 'every line is pure ASCII' );
    my @events = map { JSON::PP->new->utf8->decode($_) } @lines;
    is(
        $events[1]{violations}[0]{message}, "Indirect object syntax: write Caf\x{e9}->new(...)",
        'message decodes to the original text'
    );
};

subtest 'check --output-format jsonl: Unicode line separators are escaped' => sub {
    my $dir = project();
    $dir->child('sep.pl')->spew_utf8("use strict;\n# a\x{2028}b\x{85}c\nprint rand(10);\n");
    my ( $out, $err, $exit )
        = puff( $dir, 'check', '--output-format', 'jsonl', '--diff', '--unsafe-fixes', '--select', 'S001' );
    is( $exit, 1, 'exit 1: the diff would change something' ) or diag $err;
    my @lines = split /\n/, $out;
    is( scalar @lines, 3, 'start, file, done: one line each' );
    is( [ grep {/[^\x00-\x7f]/} @lines ], [], 'every line is pure ASCII' );
    my @events = jsonl($out);
    like( $events[1]{diff}, qr/^ # a\x{2028}b\x{85}c$/m, 'diff decodes back to the original characters' );
};

subtest 'check --output-format jsonl: no files' => sub {
    my $dir = project();
    my ( $out, $err, $exit ) = puff( $dir, 'check', '--output-format', 'jsonl' );
    is( $exit, 0, 'exit 0' ) or diag $err;
    is( $err, q{}, 'nothing on STDERR' );
    is(
        [ jsonl($out) ], [ { type => 'start', total => 0 }, { type => 'done', exit_code => 0 } ],
        'just start and done'
    );
};

subtest 'check --output-format jsonl: a run that dies still ends with done' => sub {
    my $dir  = project( 'a.pl' => 'S001/basic.pl', 'bad.pl' => 'S001/basic.pl', 'c.pl' => 'S001/basic.pl' );
    my $code = <<~'END';
        use Puff::Runner;
        no warnings 'redefine';
        my $process = \&Puff::Runner::_process;
        *Puff::Runner::_process = sub { die "runner exploded\n" if $_[1] =~ /bad/; goto &$process };
        do shift;
        die $@;
        END
    my ( $out, $err, $exit )
        = puff_with( $dir, [ '-e', $code, $PUFF ], 'check', '--output-format', 'jsonl', '--select', 'S001' );
    is( $exit, 2, 'exit 2' );
    like( $err, qr/^runner exploded$/m, 'error still on STDERR' );
    my @events = jsonl($out);
    is( [ map { $_->{type} } @events ], [qw( start file done )], 'start, the file before the die, done' );
    is(
        $events[-1], { type => 'done', exit_code => 2, error => 'runner exploded' },
        'done has exit code 2 and the error'
    );
};

subtest 'check --output-format jsonl: a run that dies before finding files is just done' => sub {
    my $dir  = project( 'a.pl' => 'S001/basic.pl' );
    my $code = <<~'END';
        use Puff::Runner;
        no warnings 'redefine';
        *Puff::Runner::files = sub { die "cannot list files\n" };
        do shift;
        die $@;
        END
    my ( $out, $err, $exit ) = puff_with( $dir, [ '-e', $code, $PUFF ], 'check', '--output-format', 'jsonl' );
    is( $exit, 2, 'exit 2' );
    like( $err, qr/^cannot list files$/m, 'error on STDERR' );
    is(
        [ jsonl($out) ], [ { type => 'done', exit_code => 2, error => 'cannot list files' } ],
        'no start: just done with the error'
    );
};

subtest 'output that cannot be written exits 2' => sub {
    plan skip_all => '/dev/full is not available' unless -c '/dev/full' && -w _;
    my $dir = project(%FILES);

    # Over 64KB of output in every format, so a write fails before the final
    # flush; the long name keeps the text output big without many violations.
    $dir->child( ( q{x} x 150 ) . q{.pl} )->spew_raw( qq{rand;\n} x 300 );
    for my $format (qw( text json jsonl )) {
        my $err = path( $dir, '..', 'stderr.txt' );
        my $pid = fork // die "fork: $!";
        if ( !$pid ) {
            chdir $dir                    or die "chdir $dir: $!";
            open STDOUT, '>', '/dev/full' or die "/dev/full: $!";
            open STDERR, '>', "$err"      or die "$err: $!";
            exec @PERL, $PUFF, 'check', '--output-format', $format, q{--select}, q{S001};
            die "exec: $!";
        }
        waitpid $pid, 0;
        is( $? >> 8, 2, "$format: exit 2" );
        like( $err->slurp_utf8, qr/^puff: cannot write output: /m, "$format: says why" );
    }
};

subtest 'rules and rule' => sub {
    my $dir = project();
    my ( $out, $err, $exit ) = puff( $dir, 'rules' );
    is( $exit, 0, 'rules exits 0' );
    like( $out, qr{^S001\s+unsafe\s+\S}m, 'S001' );
    like( $out, qr{^S002\s+unsafe\s+Use three-argument open$}m, 'S002' );
    like( $out, qr{^S003\s+unsafe\s+\S}m, 'S003' );
    like( $out, qr{^P001\s+none\s+suppression comment must list codes$}m, 'P001' );

    ( $out, $err, $exit ) = puff( $dir, 'rule', 'S002' );
    is( $exit, 0, 'rule exits 0' );
    like( $out, qr{\AS002: Use three-argument open\n}, 'code and summary' );
    like( $out, qr{^Fix safety: unsafe$}m, 'fix safety' );
    like( $out, qr{^CWE: CWE-78, CWE-73$}m, 'CWE ids' );
    like( $out, qr{^Two-argument open takes the mode}m, 'explanation' );

    ( $out, $err, $exit ) = puff( $dir, 'rule', 'P001' );
    is( $exit, 0, 'rule P001 exits 0' );
    like( $out, qr{\AP001: suppression comment must list codes\n}, 'P001 summary' );
    unlike( $out, qr{^CWE:}m, 'no CWE line for a rule without CWE ids' );

    ( $out, $err, $exit ) = puff( $dir, 'rule', 'X999' );
    is( $exit, 2, 'unknown rule exits 2' );
    like( $err, qr/Unknown rule X999/, 'error on STDERR' );

    ( $out, $err, $exit ) = puff( $dir, 'rule' );
    is( $exit, 2, 'missing code exits 2' );
};

subtest 'config file' => sub {
    my $dir = project( 'rand.pl' => 'S001/basic.pl' );
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
    my $dir = project(
        'local/lib/Rand.pm' => 'S001/basic.pl',
        't/local/x.t'       => 'S001/basic.pl',
        'vendor/x.pl'       => 'S001/basic.pl',
        'lib/ok.pm'         => 'S002/not-reported.pl',
        'lib/notes.txt'     => 'S001/basic.pl',
    );
    my ( $out, $err, $exit ) = puff( $dir, 'check', '--select', 'S001' );
    is( $exit, 1, 'vendor/x.pl still checked' );
    like( $out, qr{^vendor/x\.pl:}m, 'vendor reported' );
    unlike( $out, qr{^local/}m, 'local/ skipped' );
    like( $out, qr{^t/local/x\.t:}m, 't/local/ checked: default excludes are anchored to the root' );
    unlike( $out, qr{notes\.txt}, 'non-Perl file skipped' );

    ( $out, $err, $exit ) = puff( $dir, 'check', '--select', 'S001', './local', 't' );
    like( $out, qr{^local/lib/Rand\.pm:}m, 'files under a named ./local are checked' );
    like( $out, qr{^t/local/x\.t:}m, 'searching t/ checks t/local' );

    $dir->child('.puff.toml')->spew_utf8('');
    ( $out, $err, $exit ) = puff( $dir->child('t'), 'check', '--select', 'S001', '--config', '../.puff.toml' );
    like( $out, qr{^local/x\.t:}m, 'root is the config dir: t/local is checked from inside t/' ) or diag $err;

    $dir->child('.puff.toml')->spew_utf8(qq{exclude = ["vendor/x.pl", "/t"]\n});
    ( $out, $err, $exit ) = puff( $dir, 'check', '--select', 'S001' );
    is( $exit, 0, 'config exclude adds to the defaults; /t is anchored' ) or diag $out;

    ( $out, $err, $exit ) = puff( $dir, 'check', '--select', 'S001', 'lib/notes.txt' );
    is( $exit, 1, 'a file named explicitly is checked whatever its name' );
};

subtest 'default excludes when the searched dir is outside the root' => sub {
    my $dir = project(
        'local/lib/Rand.pm' => 'S001/basic.pl',
        'blib/lib/Rand.pm'  => 'S001/basic.pl',
        'lib/x.pl'          => 'S001/basic.pl',
    );
    my $elsewhere = $dir->parent->child(q{elsewhere});
    $elsewhere->mkpath;
    my ( $out, $err, $exit ) = puff( $elsewhere, 'check', '--select', 'S001', $dir->stringify );
    like( $out, qr{lib/x\.pl:}m, 'project files checked from another cwd' ) or diag $err;
    unlike( $out, qr{/(?:local|blib)/lib/}, 'local/ and blib/ skipped from another cwd' );

    $dir->child('ci')->mkpath;
    $dir->child( 'ci', 'puff.toml' )->spew_utf8('');
    ( $out, $err, $exit ) = puff( $dir, 'check', '--select', 'S001', '--config', 'ci/puff.toml', '.' );
    like( $out, qr{lib/x\.pl:}m, 'checked with a config in a subdirectory' ) or diag $err;
    unlike( $out, qr{^(?:local|blib)/}m, 'local/ and blib/ skipped with --config ci/puff.toml' );

    $dir->child('t')->mkpath;
    ( $out, $err, $exit ) = puff( $dir->child('t'), 'check', '--select', 'S001', '..' );
    like( $out, qr{lib/x\.pl:}m, 'parent dir checked' ) or diag $err;
    unlike( $out, qr{\.\./(?:local|blib)/}, 'local/ and blib/ skipped when searching ..' );
};

subtest 'check --statistics' => sub {
    my $dir = project(%FILES);
    my ( $out, $err, $exit ) = puff( $dir, 'check', '--statistics' );
    is( $exit, 1, 'exit 1' );
    is( $err, q{}, 'nothing on STDERR' );
    unlike( $out, qr{^\S+:\d+:\d+: }m, 'no per-violation lines' );
    like( $out, qr{^\s*\d+  S001  \[\*\*\]  \S}m, 'S001 counted with its unsafe-fix marker' );
    like( $out, qr{^\s*\d+  S002  \[\*\*\]  Use three-argument open \(\d+ fixable\)$}m, 'S002 partly fixable' );
    like( $out, qr{^Found \d+ violations \(checked 4 files\)\.$}m, 'summary still printed' );
    my @counts = $out =~ /^\s*(\d+)  [A-Z]\d{3} /mg;
    is( \@counts, [ sort { $b <=> $a } @counts ], 'most violations first' );

    for my $format (qw( json jsonl )) {
        ( $out, $err, $exit ) = puff( $dir, q{check}, q{--statistics}, q{--output-format}, $format );
        is( $exit, 2, "--statistics with $format: exit 2" );
        like( $err, qr/--statistics only works with --output-format text/, q{... with a usage error} );
        is( $out, q{}, q{... and nothing checked} );
    }

    ( $out, $err, $exit ) = puff( $dir, qw( check --show-files --statistics --output-format json ) );
    is( $exit, 0, '--show-files ignores --statistics, whatever the format' );
    like( $out, qr/\.pl$/m, '... and lists the files' );
};

subtest 'check --show-files lists files and checks nothing' => sub {
    my $dir = project( %FILES, 'local/lib/Rand.pm' => 'S001/basic.pl', 'lib/notes.txt' => 'S001/basic.pl' );
    my ( $out, $err, $exit ) = puff( $dir, 'check', '--show-files' );
    is( $exit, 0, 'exit 0 although the files have violations' );
    is( $err, q{}, 'nothing on STDERR' );
    is(
        [ sort split /\n/, $out ], [qw( bin/bareword.pl lib/declined.pl lib/two_arg.pl rand.pl )],
        'one Perl file per line; local/ and notes.txt left out'
    );

    ( $out, $err, $exit ) = puff( $dir, 'check', '--show-files', './local', 'missing.pl' );
    is( $exit, 2, 'a missing path exits 2' );
    is( $out, "local/lib/Rand.pm\n", 'a named ./local is searched' );
    like( $err, qr{^missing\.pl: error: No such file or directory$}m, 'missing path on STDERR' );
};

subtest 'extensionless perl scripts' => sub {
    my $dir = project();
    $dir->child('bin')->mkpath;
    $dir->child( 'bin', 'tool' )->spew_utf8("#!/usr/bin/env perl\nmy \$x = rand;\n");
    $dir->child( 'bin', 'sh-tool' )->spew_utf8("#!/bin/sh\nmy \$x = rand;\n");
    my ( $out, undef, $exit ) = puff( $dir, 'check', '--select', 'S001' );
    like( $out, qr{^bin/tool:2:}m, 'bin/tool with an env perl shebang is linted' );
    unlike( $out, qr{sh-tool}, 'bin/sh-tool is not' );
    is( $exit, 1, 'exit 1' );
};

subtest 'errors exit 2' => sub {
    my $dir = project( 'rand.pl' => 'S001/basic.pl' );
    my ( $out, $err, $exit ) = puff( $dir, 'check', 'missing.pl' );
    is( $exit, 2, 'missing path exits 2' );
    like( $err, qr/missing\.pl/, 'names the path' );

    my $unreadable = $dir->child('unreadable.pl');
    $unreadable->spew_utf8("1;\n");
    chmod 0, "$unreadable";
    if ( !-r $unreadable ) {
        ( $out, $err, $exit ) = puff( $dir, 'check', 'unreadable.pl' );
        is( $exit, 2, 'unreadable file exits 2' );
        like(
            $err, qr/^unreadable\.pl: error: Cannot read unreadable\.pl: .*Permission denied$/m,
            'read error without an internal source location'
        );
    }
    chmod 0644, "$unreadable";
    $unreadable->remove;

    ( $out, $err, $exit ) = puff( $dir, 'check', 'missing.pl', 'rand.pl' );
    is( $exit, 2, '2 takes priority over 1' );
    like( $out, qr/^rand\.pl:4:7: S001/m, 'other files still processed' );

    ( $out, $err, $exit ) = puff( $dir, 'check', '--output-format', 'xml' );
    is( $exit, 2, 'bad output format exits 2' );
    like( $err, qr/--output-format must be text, json or jsonl/, 'and lists the formats' );

    ( $out, $err, $exit ) = puff( $dir, 'check', '--bogus' );
    is( $exit, 2, 'unknown option exits 2' );

    ( $out, $err, $exit ) = puff( $dir, 'frobnicate' );
    is( $exit, 2, 'unknown command exits 2' );
    is( $out, '', 'nothing on STDOUT' );
    like( $err, qr/^Unrecognized command: frobnicate$/m, 'error on STDERR' );

    ( $out, $err, $exit ) = puff( $dir, 'check', '--select', 'S999' );
    is( $exit, 2, 'selecting an unknown rule exits 2' );
    like( $err, qr/^Unknown rule selector: S999$/m, 'and says so' );

    for my $option (qw( --select --extend-select --ignore )) {
        ( $out, $err, $exit ) = puff( $dir, 'check', $option, ' , ' );
        is( $exit, 2, "an empty $option exits 2" );
        like( $err, qr/^Error: $option needs a rule code or prefix$/m, 'and says so' );
    }
};

subtest 'CRLF files are linted but not fixed' => sub {
    my $dir  = project();
    my $file = $dir->child('crlf.pl');
    $file->spew_raw( corpus('S001/basic.pl')->slurp_raw =~ s/\n/\r\n/gr );
    my $before = $file->slurp_raw;
    my ( $out, $err, $exit ) = puff( $dir, 'check', '--fix', '--unsafe-fixes' );
    is( $exit, 1, 'violations remain' );
    is( $file->slurp_raw, $before, 'file unchanged' );
    like( $err, qr/^crlf\.pl: CR or CRLF line endings: fixes not applied$/m, 'reported' );
    unlike( $out, qr/\[\*\*?\]|fixable/, 'no fix offered' );
};

my @NAME_CASES = (    # [ label, name on disk (bytes), name shown (bytes) ]
    [ 'UTF-8 name', "caf\xc3\xa9", "caf\xc3\xa9" ],    # as is, not double-encoded
    [ 'Latin-1 name', "caf\xe9", 'caf\xE9' ],          # invalid byte escaped
);

# Creates $dir/$name holding $bytes, or skips the current subtest when the
# filesystem refuses the name or stores it differently (macOS normalises
# names to NFD).
sub spew_named ( $dir, $name, $bytes ) {
    my $file = $dir->child($name);
    skip_all("the filesystem refuses the name: $@") unless eval { $file->spew_raw($bytes); 1 };
    my @names = map { $_->basename } grep { $_->basename eq $name } $dir->children;
    skip_all('the filesystem changed the name') unless @names;
    return $file;
}

for my $case (@NAME_CASES) {
    my ( $label, $base, $shown ) = @$case;
    subtest "$label is shown as UTF-8, with \\xHH for invalid bytes" => sub {
        my $name = "$base.pl";
        my $want = "$shown.pl";
        my $dir  = project();
        my $file = spew_named( $dir, $name, corpus('S001/basic.pl')->slurp_raw );
        my $re   = quotemeta $want;

        my ( $out, $err, $exit ) = puff_raw( $dir, 'check' );
        is( $exit, 1, 'exit 1' );
        like( $out, qr{^${re}:4:7: S001 }m, 'text' );

        ( $out, $err, $exit ) = puff_raw( $dir, 'check', '--output-format', 'json' );
        is( JSON::PP->new->utf8->decode($out)->[0]{file}, Encode::decode( 'UTF-8', $want ), 'json' );

        ( $out, $err, $exit ) = puff_raw( $dir, 'check', '--output-format', 'jsonl' );
        my ($event) = grep { $_->{type} eq 'file' } map { JSON::PP->new->utf8->decode($_) } split /\n/, $out;
        is( $event->{file}, Encode::decode( 'UTF-8', $want ), 'jsonl file' );
        is( $event->{violations}[0]{file}, Encode::decode( 'UTF-8', $want ), 'jsonl violation file' );

        ( $out, $err, $exit ) = puff_raw( $dir, 'check', '--show-files' );
        is( $out, "$want\n", '--show-files' );

        ( $out, $err, $exit ) = puff_raw( $dir, 'check', '--diff', '--unsafe-fixes' );
        like( $out, qr{^--- a/${re}\b.*\n\+\+\+ b/${re}\b}m, '--diff headers' );

        ( $out, $err, $exit ) = puff_raw( $dir, 'check', "missing-$name" );
        like( $err, qr{^missing-${re}: error: No such file or directory$}m, 'missing path' );

        ( $out, $err, $exit ) = puff_raw( $dir, 'check', '--config', "$base.toml" );
        is( $exit, 2, 'missing --config exits 2' );
        like( $err, qr{^Config file '\Q$shown\E\.toml' not found$}m, 'missing --config' );

        chmod 0, "$file";
    SKIP: {
            skip 'chmod 0 does not stop this user reading (root?)', 1 if -r $file;
            ( $out, $err, $exit ) = puff_raw( $dir, 'check', $name );
            like( $err, qr{^${re}: error: Cannot read ${re}: }m, 'read error' );
        }
        chmod 0644, "$file";

        chmod 0555, "$dir";
    SKIP: {
            skip 'chmod 0555 does not stop this user writing (root?)', 3 if -w $dir;
            ( $out, $err, $exit ) = puff_raw( $dir, 'check', '--fix', '--unsafe-fixes', $name );
            is( $exit, 2, 'write error exits 2' );
            like( $err, qr{^${re}: error: Cannot write ${re}: .*Permission denied$}m, 'write error' );
            is( $file->slurp_raw, corpus('S001/basic.pl')->slurp_raw, 'file unchanged' );
        }
        chmod 0755, "$dir";
    };
}

subtest 'non-ASCII exclude entries' => sub {
    my $dir  = project();
    my $cafe = "caf\xc3\xa9";    # UTF-8 bytes
    skip_all("the filesystem refuses the name: $@")
        unless eval { $dir->child($cafe)->mkpath; 1 } && grep { $_->basename eq $cafe } $dir->children;
    corpus('S001/basic.pl')->copy( $dir->child( $cafe, 'a.pl' ) );
    $dir->child('.puff.toml')->spew_utf8(qq{exclude = ["caf\x{e9}"]\n});
    my ( $out, undef, $exit ) = puff_raw( $dir, 'check' );
    is( $exit, 0, 'exit 0' ) or diag $out;
    like( $out, qr{^Found 0 violations \(checked 0 files\)\.$}m, 'the excluded dir is not checked' );
};

subtest 'non-ASCII rule-paths entries' => sub {
    my $dir = project( 'a.pl' => 'S001/basic.pl' );
    $dir->child('a.pl')->append_utf8("# FIXME: tidy\n");
    my $rules = "r\xc3\xa8gles";    # UTF-8 bytes
    skip_all("the filesystem refuses the name: $@")
        unless eval { $dir->child($rules)->mkpath; 1 } && grep { $_->basename eq $rules } $dir->children;
    $root->child( 't', 'lib-rules', 'NoFixme.pm' )->copy( $dir->child($rules) );

    $dir->child('.puff.toml')->spew_utf8(qq{rule-paths = ["r\x{e8}gles-missing"]\n});
    my ( $out, $err, $exit ) = puff_raw( $dir, 'check' );
    is( $exit, 2, 'a missing rule-paths dir exits 2' );
    like( $err, qr{^rule-paths: '.*/\Q$rules\E-missing' is not a directory$}m, 'named in UTF-8' );

    $dir->child('.puff.toml')->spew_utf8(qq{rule-paths = ["r\x{e8}gles"]\nextend-select = ["X"]\n});
    ( $out, $err, $exit ) = puff_raw( $dir, 'check', 'a.pl' );
    like( $out, qr{^a\.pl:\d+:1: X001 }m, 'rules load from it' ) or diag $err;
};

done_testing;
