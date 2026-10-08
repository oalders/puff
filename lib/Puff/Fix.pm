package Puff::Fix;

use v5.36;

sub new ( $class, %args ) {
    return bless { source => $args{source}, edits => [] }, $class;
}

sub edits ($self) { $self->{edits} }

sub _check_no_heredoc ( $elem, $what ) {
    my $has = $elem->isa('PPI::Token::HereDoc')
        || ( $elem->isa('PPI::Node') && $elem->find_first('PPI::Token::HereDoc') );
    die "Cannot $what an element containing a heredoc\n" if $has;
    return;
}

sub _add ( $self, $start, $end, $text ) {
    push @{ $self->{edits} }, { start => $start, end => $end, text => $text };
    return;
}

sub replace_range ( $self, $start, $end, $text ) {
    $self->_add( $start, $end, $text );
}

sub replace ( $self, $elem, $text ) {
    _check_no_heredoc( $elem, 'replace' );
    my $src = $self->{source};
    $self->_add( $src->start_of($elem), $src->end_of($elem), $text );
}

sub insert_before ( $self, $elem, $text ) {
    _check_no_heredoc( $elem, 'insert before' );
    my $start = $self->{source}->start_of($elem);
    $self->_add( $start, $start, $text );
}

sub insert_after ( $self, $elem, $text ) {
    _check_no_heredoc( $elem, 'insert after' );
    my $end = $self->{source}->end_of($elem);
    $self->_add( $end, $end, $text );
}

sub delete ( $self, $elem ) {
    _check_no_heredoc( $elem, 'delete' );
    my $src = $self->{source};
    $self->_add( $src->start_of($elem), $src->end_of($elem), '' );
}

1;

# ABSTRACT: Rule-facing helpers that record text edits

__END__

=pod

=head1 DESCRIPTION

Records C<< {start, end, text} >> edits (character offsets) for one fix.
C<replace>, C<insert_before>, C<insert_after> and C<delete> take a PPI
element and die with a message mentioning "heredoc" when the element is or
contains a C<PPI::Token::HereDoc>; the engine treats that as the rule
declining. C<replace_range> takes raw offsets and does no such check.

=cut
