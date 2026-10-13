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

sub ids ($fixes) {
    return [ map { $_->{id} } @$fixes ];
}

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
    my %expect = ( 2 => 'ab+Rfghij', 3 => undef, 5 => 'abR+fghij' );
    for my $x ( sort keys %expect ) {
        my ( $new, undef, $def ) = Puff::Edits::apply(
            $t,
            [ fix( 2, 'r', [ 2, 5, 'R' ] ), fix( $x, 'i', [ $x, $x, '+' ] ) ]
        );
        if ( defined $expect{$x} ) {
            is ids($def), [], "insert at $x accepted";
            is $new, $expect{$x}, "insert at $x placed";
        }
        else {
            is ids($def), ['i'], "insert at $x deferred";
            is $new, 'abRfghij', 'text';
        }
    }
};

subtest 'replace after an insert' => sub {
    my ( $new, $acc, $def ) = Puff::Edits::apply(
        $t,
        [ fix( 3, 'i', [ 3, 3, '+' ] ), fix( 4, 'r', [ 2, 5, 'R' ] ) ]
    );
    is $new, 'abc+defghij', 'insert inside the range wins';
    is ids($acc), ['i'], 'insert accepted';
    is ids($def), ['r'], 'replacement deferred';

    for my $case ( [ 2, 'ab+Rfghij' ], [ 5, 'abR+fghij' ] ) {
        my ( $x, $want ) = @$case;
        ( $new, $acc, $def ) = Puff::Edits::apply(
            $t,
            [ fix( 1, 'i', [ $x, $x, '+' ] ), fix( 6, 'r', [ 2, 5, 'R' ] ) ]
        );
        is $new, $want, "insert at $x, then replacement";
        is $def, [], "insert at $x: none deferred";
    }
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
    my ( $new, undef, $def ) = Puff::Edits::apply(
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
    is ids($def), ['late'], 'late deferred';

    my @in = (
        { id => 'z', key => [ 3, 'B', 1 ], edits  => [ { start => 3, end => 3, text => 'Z' } ] },
        { id => 'y', key => [ 3, 'A', 2 ], edits  => [ { start => 3, end => 3, text => 'Y' } ] },
        { id => 'x', key => [ 3, 'A', 10 ], edits => [ { start => 3, end => 3, text => 'X' } ] },
        { id => 'w', key => [ 3, 'A', 9 ], edits  => [ { start => 3, end => 3, text => 'W' } ] },
    );
    ($new) = Puff::Edits::apply( $t, \@in );
    is $new, 'abcYWXZdefghij', 'start, code (string), line (numeric)';
};

subtest 'edits of one fix that overlap each other' => sub {
    my ( $new, $acc, $def ) = Puff::Edits::apply(
        $t,
        [ fix( 2, 'a', [ 2, 5, 'X' ], [ 4, 6, 'Y' ] ), fix( 8, 'b', [ 8, 9, '_' ] ) ]
    );
    is $new, 'abcdefgh_j', 'only the other fix applied';
    is ids($acc), ['b'], 'other fix accepted';
    is ids($def), ['a'], 'self-overlapping fix deferred';
};

subtest 'a deferred fix leaves no edits behind' => sub {
    my ( $new, $acc, $def ) = Puff::Edits::apply(
        $t,
        [
            fix( 7, 'r', [ 7, 9, 'R' ] ),
            fix( 7, 'd', [ 3, 3, 'I' ], [ 2, 4, 'X' ], [ 2, 4, 'X' ], [ 6, 8, 'Y' ] ),
            fix( 8, 'c', [ 2, 5, 'C' ] ),
        ]
    );
    is $new, 'abCfgRj', 'later fix overlapping the deferred edits applied';
    is ids($acc), [ 'r', 'c' ], 'accepted';
    is ids($def), ['d'], 'deferred';

    # The deferred fix adds a replacement before it conflicts.
    ( $new, $acc, $def ) = Puff::Edits::apply(
        $t,
        [
            fix( 6, 'r', [ 7, 9, 'R' ] ),
            fix( 7, 'd', [ 2, 4, 'X' ], [ 8, 8, 'I' ] ),
            fix( 8, 'c', [ 3, 5, 'C' ] ),
        ]
    );
    is $new, 'abcCfgRj', 'later fix overlapping the deferred replacement applied';
    is ids($acc), [ 'r', 'c' ], 'accepted';
    is ids($def), ['d'], 'deferred';

    ( $new, $acc, $def ) = Puff::Edits::apply(
        $t,
        [ fix( 2, 'a', [ 2, 4, 'X' ] ), fix( 2, 'b', [ 2, 4, 'X' ], [ 6, 7, 'Y' ] ) ]
    );
    is $new, 'abXefYhij', 'identical replacement dropped, rest of the fix applied';
    is ids($acc), [ 'a', 'b' ], 'both accepted';
};

# The algorithm Puff::Edits::apply replaced, kept as a reference.
sub reference_apply ( $text, $fixes ) {
    my $conflicts = sub ( $edit, $other ) {
        my ( $s, $e )   = @{$edit}{qw( start end )};
        my ( $os, $oe ) = @{$other}{qw( start end )};
        return $os < $s && $s < $oe if $s == $e;
        return $s < $os && $os < $e if $os == $oe;
        return $s < $oe && $os < $e;
    };
    my $same = sub ( $edit, $other ) {
        return
               $edit->{start} == $other->{start}
            && $edit->{end} == $other->{end}
            && $edit->{text} eq $other->{text};
    };
    my @sorted
        = sort { $a->{key}[0] <=> $b->{key}[0] || $a->{key}[1] cmp $b->{key}[1] || $a->{key}[2] <=> $b->{key}[2] }
        @$fixes;

    my ( @accepted, @deferred, @edits );
FIX: for my $fix (@sorted) {
        my @new;
        for my $edit ( @{ $fix->{edits} } ) {
            next if grep { $same->( $edit, $_ ) } @edits, @new;
            for my $other ( @edits, @new ) {
                if ( $conflicts->( $edit, $other ) ) {
                    push @deferred, $fix;
                    next FIX;
                }
            }
            push @new, $edit;
        }
        push @accepted, $fix;
        push @edits, @new;
    }

    my $seq     = 0;
    my @ordered = sort {
               $a->[0]{start}                     <=> $b->[0]{start}
            || ( $b->[0]{start} == $b->[0]{end} ) <=> ( $a->[0]{start} == $a->[0]{end} )
            || $a->[1]                            <=> $b->[1]
    } map { [ $_, $seq++ ] } @edits;

    for my $pair ( reverse @ordered ) {
        my $edit = $pair->[0];
        substr( $text, $edit->{start}, $edit->{end} - $edit->{start}, $edit->{text} );
    }
    return ( $text, \@accepted, \@deferred );
}

# A fixed linear congruential generator, so every run sees the same input
# and a failing round can be replayed.
my $lcg = 12345;

sub roll ($n) {
    $lcg = ( $lcg * 1103515245 + 12345 ) % 2**31;
    return ( $lcg >> 16 ) % $n;
}

subtest 'matches the reference on generated fixes' => sub {
    my $len = length $t;
    my $mismatch;
    for my $round ( 1 .. 2000 ) {
        my @fixes;
        for my $id ( 1 .. 1 + roll(6) ) {
            my @edits;
            for ( 1 .. 1 + roll(3) ) {
                my $start = roll( $len + 1 );
                my $end   = roll(10) < 4 ? $start : $start + roll( $len - $start + 1 );
                push @edits, [ $start, $end, ( 'A', 'B', '' )[ roll(3) ] ];
            }
            my $f = fix( $edits[0][0], $id, @edits );
            $f->{key}[2] = roll(3);
            push @fixes, $f;
        }
        my @got  = Puff::Edits::apply( $t, \@fixes );
        my @want = reference_apply( $t, \@fixes );
        my $ok
            = $got[0] eq $want[0]
            && "@{ ids( $got[1] ) }" eq "@{ ids( $want[1] ) }"
            && "@{ ids( $got[2] ) }" eq "@{ ids( $want[2] ) }";
        next if $ok;
        $mismatch = 1;
        is \@got, \@want, "round $round";
        last;
    }
    ok !$mismatch, 'all rounds match';
};

# Offsets that count every comparison made on them, so the test does not
# depend on timing.
package Counted {
    our $count = 0;
    use overload
        '<=>' => sub ( $x, $y, $swap ) {
        $count++;
        my $r = ( ref $x ? $$x : $x ) <=> ( ref $y ? $$y : $y );
        return $swap ? -$r : $r;
        },
        '0+'     => sub ( $x, @ ) {$$x},
        '""'     => sub ( $x, @ ) {$$x},
        fallback => 1;
    sub new ( $class, $n ) { return bless \$n, $class }
}

# Each pair of edits is accepted. Each fix after it adds an insertion and a
# replacement, then conflicts and is rolled back. Binary search keeps the
# count near n log n; checking every accepted edit would be quadratic.
subtest 'comparisons grow as n log n, with many fixes deferred' => sub {
    my $n    = 2000;
    my $text = 'x' x ( 2 * $n );
    my $at   = sub ($x) { Counted->new($x) };
    my @fixes;
    for my $i ( 0 .. $n - 1 ) {
        my $x = 2 * $i;
        push @fixes,
            {
            id    => "a$i",
            key   => [ $x, 'X001', 1 ],
            edits => [
                { start => $at->($x), end => $at->($x), text       => '+' },
                { start => $at->($x), end => $at->( $x + 1 ), text => 'y' },
            ],
            },
            {
            id    => "d$i",
            key   => [ $x, 'X002', 1 ],
            edits => [
                { start => $at->( $x + 1 ), end => $at->( $x + 1 ), text => '-' },
                { start => $at->( $x + 1 ), end => $at->( $x + 2 ), text => 'q' },
                { start => $at->($x), end       => $at->( $x + 1 ), text => 'z' },
            ],
            };
    }
    local $Counted::count = 0;
    my ( $new, $acc, $def ) = Puff::Edits::apply( $text, \@fixes );
    is scalar @$acc, $n, 'first fix of each pair accepted';
    is scalar @$def, $n, 'second fix of each pair deferred';
    is $new, '+yx' x $n, 'text';
    cmp_ok $Counted::count, '<', 20 * $n * log($n) / log(2), "comparisons: $Counted::count";
};

done_testing;
