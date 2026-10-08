package Puff::Edits;

use v5.36;

sub _conflicts ( $edit, $other ) {
    my ( $s, $e ) = @{$edit}{qw( start end )};
    my ( $os, $oe ) = @{$other}{qw( start end )};
    if ( $s == $e ) {    # insertion
        return $os < $s && $s < $oe;
    }
    if ( $os == $oe ) {    # other is an insertion
        return $s < $os && $os < $e;
    }
    return $s < $oe && $os < $e;
}

sub _same ( $edit, $other ) {
    return
           $edit->{start} == $other->{start}
        && $edit->{end} == $other->{end}
        && $edit->{text} eq $other->{text};
}

sub apply ( $text, $fixes ) {
    my @sorted = sort {
               $a->{key}[0] <=> $b->{key}[0]
            || $a->{key}[1] cmp $b->{key}[1]
            || $a->{key}[2] <=> $b->{key}[2]
    } @$fixes;

    my ( @accepted, @deferred, @edits );
    FIX: for my $fix (@sorted) {
        my @new;
        for my $edit ( @{ $fix->{edits} } ) {
            next if grep { _same( $edit, $_ ) } @edits, @new;
            for my $other (@edits) {
                if ( _conflicts( $edit, $other ) ) {
                    push @deferred, $fix;
                    next FIX;
                }
            }
            push @new, $edit;
        }
        push @accepted, $fix;
        push @edits,    @new;
    }

    # Ascending by start; at one offset insertions come first, then in
    # accepted order. Applied backwards so earlier offsets stay valid.
    my $seq = 0;
    my @ordered =
        sort {
               $a->[0]{start} <=> $b->[0]{start}
            || ( $b->[0]{start} == $b->[0]{end} ) <=> ( $a->[0]{start} == $a->[0]{end} )
            || $a->[1] <=> $b->[1]
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

Fixes are tried in C<key> order. A fix is accepted whole or deferred whole.
Two replacements conflict when their ranges overlap; an insertion at X
conflicts with a replacement C<[s,e)> only when C<s E<lt> X E<lt> e>. An edit
identical to an accepted one is dropped. Insertions at one offset keep their
accepted order.

=cut
