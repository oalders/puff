use v5.36;
use Test2::V0;

use JSON::PP              ();
use Puff::Reporter::JSONL ();
use Puff::Violation       ();

# A reporter writing to an in-memory buffer, and a reader for its lines.
sub reporter () {
    my $buf = q{};
    open my $fh, '>', \$buf or die "open: $!";
    my $reporter = Puff::Reporter::JSONL->new( out => $fh );
    return ( $reporter, sub { [ split /\n/, $buf, -1 ] } );
}

my $json = JSON::PP->new;

subtest 'start once' => sub {
    my ( $reporter, $lines ) = reporter();
    my $progress = $reporter->progress;
    $progress->( $_, 2 ) for 0 .. 2;
    is( $lines->(), [ '{"total":2,"type":"start"}', q{} ], 'one start event, then a newline' );
};

subtest 'file' => sub {
    my ( $reporter, $lines ) = reporter();
    my $violation = Puff::Violation->new( code => 'T001', message => 'foo', file => 'a.pl', line => 3, column => 5 );
    $reporter->on_file->( { file => 'a.pl', violations => [$violation], fixed_count => 2, diff => 'DIFF' } );
    $reporter->on_file->( { file => 'b.pl', violations => [], error => 'boom', fixes_skipped => 'CR' } );
    my @events = map { $json->decode($_) } grep {length} @{ $lines->() };
    is(
        \@events,
        [
            {
                type          => 'file',
                file          => 'a.pl',
                error         => undef,
                fixed         => 2,
                fixes_skipped => undef,
                diff          => 'DIFF',
                violations    => [ {
                    code    => 'T001',
                    message => 'foo',
                    file    => 'a.pl',
                    line    => 3,
                    column  => 5,
                    fix     => { safety => 'none', available => bool(0), applied => bool(0) },
                } ],
            },
            {
                type          => 'file',
                file          => 'b.pl',
                error         => 'boom',
                fixed         => 0,
                fixes_skipped => 'CR',
                diff          => undef,
                violations    => [],
            },
        ],
        'file events'
    );
};

subtest 'one ASCII line per event' => sub {
    my ( $reporter, $lines ) = reporter();
    my $name = "a\x{2028}b\x{2029}c\x{85}d\ne\x{e9}.pl";
    $reporter->on_file->( { file => $name, violations => [], error => "bad\x{2028}\x{85}\n\x{e9}" } );
    my @lines = @{ $lines->() };
    is( scalar @lines, 2, 'one line' );
    is( $lines[1],     q{}, 'ending in a newline' );
    like( $lines[0], qr/\A[\x20-\x7e]+\z/, 'printable ASCII only' );
    my $event = $json->decode( $lines[0] );
    is( $event->{file},  $name,                    'file decodes back' );
    is( $event->{error}, "bad\x{2028}\x{85}\n\x{e9}", 'error decodes back' );
};

subtest 'DEL is escaped' => sub {
    my ( $reporter, $lines ) = reporter();
    $reporter->on_file->( { file => "a\x7fb.pl", violations => [] } );
    my $line = $lines->()->[0];
    like( $line, qr/"a\\u007fb\.pl"/, 'DEL is \u007f' );
    like( $line, qr/\A[\x20-\x7e]+\z/, 'printable ASCII only' );
    is( $json->decode($line)->{file}, "a\x7fb.pl", 'and decodes back' );
};

subtest 'fatal part way' => sub {
    my ( $reporter, $lines ) = reporter();
    $reporter->progress->( 0, 2 );
    $reporter->on_file->( { file => 'a.pl', violations => [] } );
    $reporter->fatal("boom\n");
    my @events = map { $json->decode($_) } grep {length} @{ $lines->() };
    is( scalar @events, 3, 'three events' );
    is( [ map { $_->{type} } @events ], [qw( start file done )], 'start, file, done' );
    is( $events[-1], { type => 'done', exit_code => 2, error => 'boom' }, 'done has exit code 2 and the error' );
};

subtest 'done and fatal' => sub {
    my ( $reporter, $lines ) = reporter();
    $reporter->report( { exit_code => 1 }, undef, undef );
    $reporter->fatal("Can't open dir: Permission denied at x line 3.\n");
    is(
        [ map { $json->decode($_) } grep {length} @{ $lines->() } ],
        [
            { type => 'done', exit_code => 1 },
            { type => 'done', exit_code => 2, error => "Can't open dir: Permission denied at x line 3." },
        ],
        'done, and done with the error'
    );
};

done_testing;
