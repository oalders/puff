use v5.36;
use Test2::V0;

use Puff::Edits ();

my $t = 'abcdefghij';

sub fix ( $key_start, $id, @edits ) {
    return {
        id    => $id,
        key   => [ $key_start, 'X001', 1 ],
        edits => [ map { { start => $_->[0], end => $_->[1], text => $_->[2] } } @edits ],
    };
}

sub ids ($fixes) { return [ map { $_->{id} } @$fixes ] }

subtest 'one replace' => sub {
    my ( $new, $acc, $def ) = Puff::Edits::apply( $t, [ fix( 2, 'a', [ 2, 4, 'XY' ] ) ] );
    is $new, 'abXYefghij', 'replaced';
    is ids($acc), ['a'], 'accepted';
    is $def, [], 'none deferred';
};

subtest 'non-overlapping fixes applied from the end' => sub {
    my ( $new, $acc, $def ) = Puff::Edits::apply(
        $t,
        [ fix( 2, 'a', [ 2, 4, 'XYZ' ] ), fix( 6, 'b', [ 6, 8, '_' ] ) ]
    );
    is $new, 'abXYZef_ij', 'both applied';
    is ids($acc), [ 'a', 'b' ], 'both accepted';
    is $def, [], 'none deferred';
};

subtest 'overlapping replaces' => sub {
    my ( $new, $acc, $def ) = Puff::Edits::apply(
        $t,
        [ fix( 2, 'a', [ 2, 5, 'X' ] ), fix( 4, 'b', [ 4, 6, 'Y' ] ) ]
    );
    is $new, 'abXfghij', 'first applied only';
    is ids($acc), ['a'], 'first accepted';
    is ids($def), ['b'], 'second deferred';
};

subtest 'insert vs replace' => sub {
    my %expect = ( 3 => 'defer', 2 => 'ok', 5 => 'ok' );
    for my $x ( sort keys %expect ) {
        my ( $new, $acc, $def ) = Puff::Edits::apply(
            $t,
            [ fix( 2, 'r', [ 2, 5, 'R' ] ), fix( $x, 'i', [ $x, $x, '+' ] ) ]
        );
        if ( $expect{$x} eq 'defer' ) {
            is ids($def), ['i'], "insert at $x deferred";
            is $new, 'abRfghij', 'text';
        }
        else {
            is ids($def), [], "insert at $x accepted";
            like $new, qr/\+/, 'inserted';
        }
    }
    my ($new) = Puff::Edits::apply( $t, [ fix( 2, 'r', [ 2, 5, 'R' ] ), fix( 2, 'i', [ 2, 2, '+' ] ) ] );
    is $new, 'ab+Rfghij', 'insert at start goes before replacement';
    ($new) = Puff::Edits::apply( $t, [ fix( 2, 'r', [ 2, 5, 'R' ] ), fix( 5, 'i', [ 5, 5, '+' ] ) ] );
    is $new, 'abR+fghij', 'insert at end goes after replacement';
};

subtest 'identical edits are dropped' => sub {
    my ( $new, $acc, $def ) = Puff::Edits::apply(
        $t,
        [ fix( 3, 'a', [ 3, 3, 'use X;' ] ), fix( 3, 'b', [ 3, 3, 'use X;' ] ) ]
    );
    is $new, 'abcuse X;defghij', 'inserted once';
    is ids($acc), [ 'a', 'b' ], 'both accepted';
    is $def, [], 'none deferred';
};

subtest 'all or nothing' => sub {
    my ( $new, $acc, $def ) = Puff::Edits::apply(
        $t,
        [
            fix( 2, 'a', [ 2, 5, 'X' ] ),
            fix( 4, 'b', [ 0, 1, 'Q' ], [ 4, 6, 'Y' ] ),
        ]
    );
    is $new, 'abXfghij', 'second fix not applied at all';
    is ids($def), ['b'], 'deferred';
};

subtest 'same-offset inserts keep accepted order' => sub {
    my ($new) = Puff::Edits::apply(
        $t,
        [ fix( 3, 'a', [ 3, 3, 'A' ] ), fix( 3, 'b', [ 3, 3, 'B' ] ) ]
    );
    is $new, 'abcABdefghij', 'A then B';
};

subtest 'order comes from key' => sub {
    my ( $new, $acc, $def ) = Puff::Edits::apply(
        $t,
        [ fix( 4, 'late', [ 4, 6, 'Y' ] ), fix( 2, 'early', [ 2, 5, 'X' ] ) ]
    );
    is $new, 'abXfghij', 'early wins';
    is ids($acc), ['early'], 'early accepted';
    is ids($def), ['late'],  'late deferred';

    my @in = (
        { id => 'z', key => [ 3, 'B', 1 ], edits => [ { start => 3, end => 3, text => 'Z' } ] },
        { id => 'y', key => [ 3, 'A', 2 ], edits => [ { start => 3, end => 3, text => 'Y' } ] },
        { id => 'x', key => [ 3, 'A', 10 ], edits => [ { start => 3, end => 3, text => 'X' } ] },
        { id => 'w', key => [ 3, 'A', 9 ], edits => [ { start => 3, end => 3, text => 'W' } ] },
    );
    ($new) = Puff::Edits::apply( $t, \@in );
    is $new, 'abcYWXZdefghij', 'start, code (string), line (numeric)';
};

done_testing;
