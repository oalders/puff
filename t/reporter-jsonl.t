use v5.36;
use Test2::V0;

use JSON::PP              ();
use Puff::Reporter::JSONL ();
use Puff::Violation       ();

# Runs $code with a JSONL reporter writing to a string; returns the decoded
# events.
sub events ( $mode, $code ) {
    my $buffer = q{};
    open my $out, '>', \$buffer or die "in-memory handle: $!";
    $code->( Puff::Reporter::JSONL->new( out => $out, mode => $mode ), $out );
    close $out or die "close: $!";
    return [ map { JSON::PP->new->decode($_) } split /\n/, $buffer ];
}

my $violation
    = Puff::Violation->new( code => 'X001', message => 'msg', file => 'a.pl', line => 2, column => 3, fixable => 0 );

subtest 'start, file and done' => sub {
    my $events = events(
        'lint',
        sub ( $jsonl, $out ) {
            $jsonl->start(1);
            $jsonl->file( { file => 'a.pl', violations => [$violation] } );
            $jsonl->report( { exit_code => 1 }, $out, undef );
        }
    );
    is(
        $events,
        [
            { type => 'start', total => 1 },
            {
                type          => 'file',
                file          => 'a.pl',
                error         => undef,
                fixes_skipped => undef,
                fixed         => 0,
                violations    => [
                    {
                        code    => 'X001',
                        message => 'msg',
                        file    => 'a.pl',
                        line    => 2,
                        column  => 3,
                        fix     => { safety => 'none', available => bool(0), applied => bool(0) },
                    }
                ],
            },
            { type => 'done', exit_code => 1 },
        ],
        'one event per call; report ignores its error handle'
    );
};

subtest 'diff mode adds diff, written files count fixes' => sub {
    my $events = events(
        'diff',
        sub ( $jsonl, $out ) {
            $jsonl->file( { file => 'a.pl', diff    => "--- a\n" } );
            $jsonl->file( { file => 'b.pl', written => 1, fixed_count => 2 } );
        }
    );
    is( $events->[0]{diff}, "--- a\n", 'diff is in the event' );
    is( $events->[1]{diff}, undef, 'null when there is none' );
    is( $events->[1]{fixed}, 2, 'fixed counts written fixes' );
};

subtest 'abort before start is just done' => sub {
    my $events = events( 'lint', sub ( $jsonl, $out ) { $jsonl->abort( 2, "it broke\n" ) } );
    is(
        $events, [ { type => 'done', exit_code => 2, error => 'it broke' } ],
        'done with the error, trailing newline removed'
    );
};

subtest 'a failed write dies' => sub {
    my $buffer = q{};
    open my $out, '<', \$buffer or die "in-memory handle: $!";    # read-only, so writes fail
    my $jsonl = Puff::Reporter::JSONL->new( out => $out );
    my $error = dies { no warnings 'io'; $jsonl->start(0) };
    like( $error, qr/^puff: cannot write output: /, 'dies instead of losing the event' );
};

done_testing;
