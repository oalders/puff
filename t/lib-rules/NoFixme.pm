package Local::Rule::NoFixme;

use v5.36;
use parent 'Puff::Rule';

sub code       {'X001'}
sub summary    {'Use TODO instead of FIXME'}
sub applies_to {'PPI::Token::Comment'}
sub fix_safety {'safe'}
sub options    { { keyword => 'FIXME' } }

sub explanation {
    return <<~'END';
        This project marks open work with TODO. A FIXME comment is reported
        and the fix rewrites it as TODO. The word to look for can be changed
        with the `keyword` option.
        END
}

sub check ( $self, $elem, $doc ) {
    my $keyword = $self->option('keyword');
    return unless $elem->content =~ /\b\Q$keyword\E\b/;
    return $self->violation( $elem, message => "Use TODO instead of $keyword" );
}

sub fix ( $self, $violation, $fix ) {
    my $elem    = $violation->element;
    my $keyword = $self->option('keyword');
    return 0 unless $elem->content =~ /\b\Q$keyword\E\b/;

    my $start = $fix->source->start_of($elem) + $-[0];
    $fix->replace_range( $start, $start + length $keyword, 'TODO' );
    return 1;
}

1;
