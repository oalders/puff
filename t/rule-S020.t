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
        [ 3, 9, 'HTTP::Tiny timeout => 0 makes every read and write give up at once (CWE-400)', 0 ],
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

for my $bad ( 0, -5, 'abc', [60], 'inf', '-inf', 'nan', 9**9**9 ) {
    like(
        dies { $class->new( options => { 'max-timeout' => $bad } ) },
        qr/rules\.S020\.max-timeout must be a positive, finite number/,
        'max-timeout ' . ( ref $bad ? 'list' : $bad ) . ' is rejected'
    );
}

is(
    messages(
              "my \$a = LWP::UserAgent->new( timeout => 5 );\n\$a->timeout(0);\n"
            . "my \$b = HTTP::Tiny->new( timeout => undef );\n"
            . "my \$c = LWP::UserAgent->new;\n\$c->timeout(undef);\n"
            . "my \$d = Furl->new( timeout => -5 );\n"
            . "my \$e = LWP::UserAgent->new( timeout => '1e9' );\n"
            . "my \$f = Mojo::UserAgent->new( request_timeout => 5 );\n\$f->connect_timeout(- 2);\n"
    ),
    [
        [ 1, 9, 'LWP::UserAgent ->timeout(0) means no usable timeout (CWE-400)', 0 ],
        [ 3, 9, 'HTTP::Tiny timeout => undef leaves the 60s default (CWE-400)', 0 ],
        [ 4, 9, 'LWP::UserAgent ->timeout(undef) means no timeout (CWE-400)', 0 ],
        [ 6, 9, 'Furl timeout => -5 is not a usable timeout (CWE-400)', 0 ],
        [ 7, 9, q{LWP::UserAgent timeout => '1e9' is longer than max-timeout (60s) (CWE-400)}, 0 ],
        [ 8, 9, 'Mojo::UserAgent ->connect_timeout(-2) is not a usable timeout (CWE-400)', 0 ],
    ],
    'setter, undef, negative and quoted values'
);

# The setters are found by one pass over each statement list, not a scan
# of the scope per client, so a file with many clients stays fast.
{
    my $pairs  = join q{}, map {"my \$ua$_ = LWP::UserAgent->new;\n\$ua$_->timeout(5);\n"} 1 .. 2000;
    my $text   = "$pairs\nsub f {\n$pairs}\n";
    my $orig   = \&Puff::Rule::Security::HTTPTimeout::_build_index;
    my $builds = 0;
    no warnings 'redefine';
    local *Puff::Rule::Security::HTTPTimeout::_build_index = sub { $builds++; goto &$orig };
    my $start = time;
    is( violations($text), [], 'many clients with setters' );
    is( $builds, 2, 'one index per statement list' );
    cmp_ok( time - $start, '<', 10, 'many clients are checked quickly' );
}

# Each client looks only at the uses of its name that follow it, so many
# clients reusing one name stay linear. The use lists are tied to count
# the entries read.
{

    package CountFetch {
        use parent -norequire, 'Tie::StdArray';
        our $fetches = 0;
        sub FETCH { $fetches++; return $_[0]->SUPER::FETCH( $_[1] ) }
    }
    require Tie::Array;
    my $clients = 2000;
    my $text    = join q{}, map {"my \$ua = LWP::UserAgent->new;\n\$ua->timeout(5);\n"} 1 .. $clients;
    my $orig    = \&Puff::Rule::Security::HTTPTimeout::_build_index;
    no warnings 'redefine';
    local *Puff::Rule::Security::HTTPTimeout::_build_index = sub {
        my $index = $orig->(@_);
        for my $uses ( values %{ $index->{uses} } ) {
            my @copy = @$uses;
            tie @$uses, 'CountFetch';
            @$uses = @copy;
        }
        return $index;
    };
    local $CountFetch::fetches = 0;
    is( violations($text), [], 'many clients reusing one name' );
    cmp_ok( $CountFetch::fetches, '<', 5 * $clients, 'the uses of a name are not rescanned per client' );
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
