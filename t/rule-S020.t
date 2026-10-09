use v5.36;
use Test2::V0;

use Puff::Engine ();
use Puff::Rules  ();
use Puff::Source ();
use Puff::Test   qw( run_corpus );

run_corpus('S020');

my @classes = Puff::Rules->load;
my ($class) = grep { $_->code eq 'S020' } @classes;

sub violations ( $text, $options = {} ) {
    my $result = Puff::Engine->new( rules => [ $class->new( options => $options ) ] )
        ->process_source( Puff::Source->from_string($text), file => 'x.pl' );
    return $result->{violations};
}

sub messages ( $text, $options = {} ) {
    return [ map { [ $_->line, $_->column, $_->message, $_->fixable ] } @{ violations( $text, $options ) } ];
}

is(
    messages(
              "my \$a = LWP::UserAgent->new;\nmy \$b = Mojo::UserAgent->new;\n"
            . "my \$c = HTTP::Tiny->new( timeout => 0 );\nmy \$d = Furl->new( timeout => 61 );\n"
            . "my \$e = LWP::UserAgent->new;\n\$e->timeout(90);\n"
    ),
    [
        [
            1, 9,
            'LWP::UserAgent created without a timeout (the 180s default); set one of at most 60s (CWE-400)', 0
        ],
        [
            2, 9,
            'Mojo::UserAgent created without a request_timeout or inactivity_timeout'
                . ' (request_timeout defaults to no limit); set one of at most 60s (CWE-400)',
            0
        ],
        [ 3, 9, 'HTTP::Tiny timeout => 0 means no usable timeout (CWE-400)', 0 ],
        [ 4, 9, 'Furl timeout => 61 is longer than max-timeout (60s) (CWE-400)', 0 ],
        [ 5, 9, 'LWP::UserAgent ->timeout(90) is longer than max-timeout (60s) (CWE-400)', 0 ],
    ],
    'messages, positions and no fix'
);

my $text = "my \$a = LWP::UserAgent->new( timeout => 30 );\nmy \$b = HTTP::Tiny->new( timeout => 120 );\n"
    . "my \$c = LWP::UserAgent->new;\n";
is( [ map { $_->line } @{ violations($text) } ], [ 2, 3 ], 'default max-timeout is 60' );
is( [ map { $_->line } @{ violations( $text, { 'max-timeout' => 20 } ) } ], [ 1, 2, 3 ], 'max-timeout 20' );
is( [ map { $_->line } @{ violations( $text, { 'max-timeout' => 120 } ) } ], [3], 'max-timeout 120' );
is(
    [ map { $_->line } @{ violations( $text, { 'max-timeout' => 1000 } ) } ],
    [3], 'a missing timeout is reported whatever max-timeout is'
);
is( [ map { $_->line } @{ violations( $text, { 'max-timeout' => 29.5 } ) } ], [ 1, 2, 3 ], 'a fractional max' );

for my $bad ( 0, -5, 'abc', [60] ) {
    like(
        dies { $class->new( options => { 'max-timeout' => $bad } ) },
        qr/rules\.S020\.max-timeout must be a positive number/,
        'max-timeout ' . ( ref $bad ? 'list' : $bad ) . ' is rejected'
    );
}

is( $class->fix_safety, 'none', 'no fix' );
is( [ $class->cwe ], [400], 'CWE-400' );

sub selected (@select) {
    return [ grep { $_ eq 'S020' } map { $_->code } Puff::Rules->instantiate( \@classes, select => [@select] ) ];
}
is( selected( 'S', 'B' ), [], 'not selected by the default prefixes' );
is( selected('S02'), [], 'not selected by a longer prefix' );
is( selected('S020'), ['S020'], 'selected by its exact code' );
is( selected('ALL'), ['S020'], 'selected by ALL' );

done_testing;
