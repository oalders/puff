use v5.36;
use Test2::V0;

use JSON::PP             ();
use Puff::Reporter::JSON ();
use Puff::Reporter::Text ();
use Puff::Engine         ();
use Puff::Source         ();

# One rule, declared unsafe overall, whose violations carry their own
# safety: `safe` words are safe to fix, `risky` words are not.
package MixedRule {
    use v5.36;
    use parent 'Puff::Rule';

    sub code       {'X900'}
    sub summary    {'mixed safety'}
    sub applies_to {'PPI::Token::Word'}
    sub fix_safety {'unsafe'}

    sub check ( $self, $elem, $doc ) {
        my $word = $elem->content;
        return unless $word eq 'safe' || $word eq 'risky';
        return $self->violation( $elem, fix_safety => $word eq 'safe' ? 'safe' : 'unsafe' );
    }
}

package main;

my $engine = Puff::Engine->new( rules => [ MixedRule->new ], fix_mode => 'none' );
my $result = $engine->process_source( Puff::Source->from_string("safe;\nrisky;\n"), file => 'x.pl' );
my $run    = { exit_code => 1, files => [ { file => 'x.pl', violations => $result->{violations} } ] };

sub render ( $reporter, $run ) {
    my $buffer = q{};
    open my $out, '>', \$buffer or die "in-memory handle: $!";
    $reporter->report( $run, $out, \*STDERR );
    close $out or die "close: $!";
    return $buffer;
}

subtest 'text markers follow each violation' => sub {
    my $text = render( Puff::Reporter::Text->new( fix_mode => 'safe' ), $run );
    like( $text, qr/^x\.pl:1:1: X900 .* \[\*\]$/m, 'safe violation is [*]' );
    like( $text, qr/^x\.pl:2:1: X900 .* \[\*\*\]$/m, 'unsafe violation is [**]' );

    $text = render( Puff::Reporter::Text->new( fix_mode => 'unsafe' ), $run );
    unlike( $text, qr/\[\*\*\]/, 'no [**] when unsafe fixes are enabled' );
    is( [ $text =~ /\[\*\]$/mg ], [ '[*]', '[*]' ], 'both are [*]' );
};

subtest 'JSON safety follows each violation' => sub {
    my $items = JSON::PP->new->decode( render( Puff::Reporter::JSON->new, $run ) );
    is( [ map { $_->{fix}{safety} } @$items ], [ 'safe', 'unsafe' ], 'per-violation safety' );
};

done_testing;
