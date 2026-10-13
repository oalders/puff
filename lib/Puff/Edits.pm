package Puff::Edits;

use v5.36;

# Index of the first edit in the start-sorted @$list that starts at or after
# $x, or strictly after $x when $after is true.
sub _bisect ( $list, $x, $after = 0 ) {
    my ( $lo, $hi ) = ( 0, scalar @$list );
    while ( $lo < $hi ) {
        my $mid = ( $lo + $hi ) >> 1;
        my $s   = $list->[$mid]{start};
        if   ( $after ? $s <= $x : $s < $x ) { $lo = $mid + 1 }
        else                                 { $hi = $mid }
    }
    return $lo;
}

# $reps and $ins hold the edits accepted so far: replacements and insertions,
# each sorted by start. Accepted replacements never overlap, so they are also
# sorted by end, and the last one starting before $e is the only one that can
# reach past $s.
sub _conflicts ( $edit, $reps, $ins ) {
    my ( $s, $e ) = @{$edit}{qw( start end )};
    my $i = _bisect( $reps, $e );
    return 1 if $i > 0 && $reps->[ $i - 1 ]{end} > $s;
    return 0 if $s == $e;    # insertions never conflict with each other
    my $j = _bisect( $ins, $s, 1 );
    return $j < @$ins && $ins->[$j]{start} < $e;
}

sub _key ($edit) {
    return join ',', @{$edit}{qw( start end text )};
}

sub apply ( $text, $fixes ) {
    my @sorted
        = sort { $a->{key}[0] <=> $b->{key}[0] || $a->{key}[1] cmp $b->{key}[1] || $a->{key}[2] <=> $b->{key}[2] }
        @$fixes;

    my ( @accepted, @deferred, @edits, @reps, @ins, %seen );
FIX: for my $fix (@sorted) {
        my @new;
        for my $edit ( @{ $fix->{edits} } ) {
            next if $seen{ _key($edit) };
            if ( _conflicts( $edit, \@reps, \@ins ) ) {

                # Undo this fix's edits, newest first, so each insertion is
                # still the last one at its offset.
                for my $undo ( reverse @new ) {
                    delete $seen{ _key($undo) };
                    if ( $undo->{start} == $undo->{end} ) {
                        splice @ins, _bisect( \@ins, $undo->{start}, 1 ) - 1, 1;
                    }
                    else {
                        splice @reps, _bisect( \@reps, $undo->{start} ), 1;
                    }
                }
                push @deferred, $fix;
                next FIX;
            }
            $seen{ _key($edit) } = 1;
            if ( $edit->{start} == $edit->{end} ) {
                splice @ins, _bisect( \@ins, $edit->{start}, 1 ), 0, $edit;
            }
            else {
                splice @reps, _bisect( \@reps, $edit->{start} ), 0, $edit;
            }
            push @new, $edit;
        }
        push @accepted, $fix;
        push @edits, @new;
    }

    # Ascending by start; at one offset insertions come first, then in
    # accepted order. Applied backwards so earlier offsets stay valid.
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

1;

# ABSTRACT: Apply non-conflicting text edits grouped into all-or-nothing fixes

__END__

=pod

=head1 DESCRIPTION

Pure text, no PPI. C<apply($text, \@fixes)> takes fixes of the form
C<< { edits => [ { start, end, text } ], key => [ $start, $code, $line ], id => ... } >>
with half-open character offsets, and returns C<($new_text, \@accepted,
\@deferred)>.

Fixes are tried in C<key> order. A fix is accepted whole or deferred whole;
it is deferred when one of its edits conflicts with an accepted edit or with
another of its own edits. Two replacements conflict when their ranges overlap; an insertion at X
conflicts with a replacement C<[s,e)> only when C<s E<lt> X E<lt> e>. An edit
identical to an accepted one is dropped. Insertions at one offset keep their
accepted order.

Accepted edits are kept sorted by start, so each new edit is checked against
its neighbours with a binary search rather than against every accepted edit.

=cut
