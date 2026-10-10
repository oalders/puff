use v5.36;
use Test2::V0;

use PPI           ();
use Puff::PPIUtil qw( is_builtin_call call_args is_sole_subscript_key );

my @cases = (
    [ 'open(FH, "<$f");', 1, 'FH|"<$f"' ],
    [ 'open FH, $f or die;', 1, 'FH|$f' ],
    [ q{open my $fh, '<', $f or die "x";}, 1, q{my $fh|'<'|$f} ],
    [ 'open(FH, $f) || die;', 1, 'FH|$f' ],
    [ 'open FH, $f if $x;', 1, 'FH|$f' ],
    [ '$obj->open(1, 2);', 0 ],
    [ 'my %h = (open => 1);', 0 ],
    [ '$h{rand};', 0 ],
    [ 'sub rand { }', 0 ],
    [ 'my $x = rand(10);', 1, '10' ],
    [ 'my $x = rand;', 1, '' ],
    [ 'open(FH, join(",", @a));', 1, 'FH|join (",", @a)' ],
    [ 'package rand;', 0 ],
    [ 'use open qw(:std);', 0 ],
);

for my $case (@cases) {
    my ( $code, $builtin, $args ) = @{$case};
    subtest $code => sub {
        my $doc  = PPI::Document->new( \$code );
        my $word = $doc->find_first(
            sub ( $top, $el ) { $el->isa('PPI::Token::Word') && $el->content =~ /\A(?:open|rand)\z/ } );
        ok( $word, 'found word' ) or return;
        is( is_builtin_call($word) ? 1 : 0, $builtin, 'is_builtin_call' );
        return unless $builtin;
        is(
            join(
                '|',
                map {
                    join ' ',
                        map { $_->content } @{$_}
                } @{ call_args($word) }
            ),
            $args,
            'args'
        );
    };
}

my @subscript_cases = (
    [ q{$h{'k'};}, 1 ],
    [ q{$h->{ "k" };}, 1 ],
    [ q{@h{'k'};}, 1 ],
    [ q{@h{'k', 'j'};}, 0 ],
    [ q{$h{'k' . $x};}, 0 ],
    [ q{$a['k'];}, 0 ],
    [ q{${'k'};}, 0 ],
    [ q{f('k');}, 0 ],
);

for my $case (@subscript_cases) {
    my ( $code, $want ) = @{$case};
    my $doc   = PPI::Document->new( \$code );
    my $quote = $doc->find_first('PPI::Token::Quote');
    is( is_sole_subscript_key($quote) ? 1 : 0, $want, "is_sole_subscript_key: $code" );
}

done_testing;
