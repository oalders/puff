use v5.36;
use Test2::V0;

use JSON::PP             ();
use Puff::Reporter::JSON ();
use Puff::Reporter::Text ();
use Puff::Engine         ();
use Puff::Source         ();
use Puff::Violation      ();

# One rule, declared unsafe overall, whose violations carry their own
# safety: `safe` words are safe to fix, `risky` words are not, and `odd`
# words carry a safety that is neither.
package MixedRule {
    use v5.36;
    use parent 'Puff::Rule';

    sub code       {'X900'}
    sub summary    {'mixed safety'}
    sub applies_to {'PPI::Token::Word'}
    sub fix_safety {'unsafe'}

    sub check ( $self, $elem, $doc ) {
        my $word = $elem->content;
        return $self->violation( $elem, message => 'safe word', fix_safety  => 'safe' ) if $word eq 'safe';
        return $self->violation( $elem, message => 'risky word', fix_safety => 'unsafe' ) if $word eq 'risky';
        return unless $word eq 'odd';

        # Rule::violation dies on a bad fix_safety, so build it directly.
        return Puff::Violation->new(
            rule       => $self,
            code       => $self->code,
            element    => $elem,
            line       => $elem->location->[0],
            column     => $elem->location->[1],
            message    => 'odd word',
            fixable    => 1,
            fix_safety => 'bogus',
        );
    }
}

# A rule with no fix whose violation still claims a safe one.
package NoFixRule {
    use v5.36;
    use parent 'Puff::Rule';

    sub code       {'X901'}
    sub summary    {'no fix'}
    sub applies_to {'PPI::Token::Word'}

    sub check ( $self, $elem, $doc ) {
        return unless $elem->content eq 'nofix';

        # Rule::violation would clear fixable, so build it directly.
        return Puff::Violation->new(
            rule       => $self,
            code       => $self->code,
            element    => $elem,
            line       => $elem->location->[0],
            column     => $elem->location->[1],
            message    => 'nofix word',
            fixable    => 1,
            fix_safety => 'safe',
        );
    }
}

package main;

my $engine = Puff::Engine->new( rules => [ MixedRule->new, NoFixRule->new ], fix_mode => 'none' );
my $result = $engine->process_source( Puff::Source->from_string("safe;\nrisky;\nodd;\nnofix;\n"), file => 'x.pl' );
my $run    = { exit_code => 1, files => [ { file => 'x.pl', violations => $result->{violations} } ] };

sub render ( $reporter, $run ) {
    my $buffer = q{};
    open my $out, '>', \$buffer or die "in-memory handle: $!";
    $reporter->report( $run, $out, \*STDERR );
    close $out or die "close: $!";
    return $buffer;
}

subtest 'text markers follow each violation' => sub {
    for my $mode (qw( safe none )) {
        my $text = render( Puff::Reporter::Text->new( fix_mode => $mode ), $run );
        like( $text, qr/^x\.pl:1:1: X900 safe word \[\*\]$/m, "safe violation is [*] in $mode mode" );
        like( $text, qr/^x\.pl:2:1: X900 risky word \[\*\*\]$/m, "unsafe violation is [**] in $mode mode" );
        like( $text, qr/^x\.pl:3:1: X900 odd word$/m, "unknown safety has no marker in $mode mode" );
        like( $text, qr/^x\.pl:4:1: X901 nofix word$/m, "rule with no fix has no marker in $mode mode" );
        like( $text, qr/^1 fixable with --fix$/m, "only the safe violation is counted in $mode mode" );
    }

    my $text = render( Puff::Reporter::Text->new( fix_mode => 'unsafe' ), $run );
    like( $text, qr/^x\.pl:1:1: X900 safe word \[\*\]$/m, 'safe violation is [*] in unsafe mode' );
    like( $text, qr/^x\.pl:2:1: X900 risky word \[\*\]$/m, 'unsafe violation is [*] in unsafe mode' );
    like( $text, qr/^x\.pl:3:1: X900 odd word$/m, 'unknown safety has no marker in unsafe mode' );
    like( $text, qr/^x\.pl:4:1: X901 nofix word$/m, 'rule with no fix has no marker in unsafe mode' );
    like( $text, qr/^2 fixable with --fix$/m, 'safe and unsafe violations are counted in unsafe mode' );

    $text = render( Puff::Reporter::Text->new( fix_mode => 'safe', statistics => 1 ), $run );
    like( $text, qr/^\s*1\s+X901\s+no fix$/m, 'rule with no fix is not counted as fixable in statistics' );
};

subtest 'JSON safety follows each violation' => sub {
    my $items = JSON::PP->new->decode( render( Puff::Reporter::JSON->new, $run ) );
    is( [ map { $_->{fix}{safety} } @$items[ 0, 1 ] ], [ 'safe', 'unsafe' ], 'per-violation safety' );
    is( $items->[2]{fix}, { safety => 'bogus', available => T(), applied => F() }, 'unknown safety is passed through' );
    is(
        $items->[3]{fix}, { safety => 'none', available => F(), applied => F() },
        'rule with no fix wins over the violation'
    );
};

done_testing;
