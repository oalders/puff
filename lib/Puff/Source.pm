package Puff::Source;

use v5.36;

use Encode     ();
use Path::Tiny qw( path );

my $BOM = "\xEF\xBB\xBF";

sub from_file ( $class, $path ) {
    my $bytes = eval { path($path)->slurp_raw };
    die "Cannot read $path: " . ( "$@" =~ s/ at \S+ line \d+\.?\s*\z|\s+\z//r ) . "\n" unless defined $bytes;

    my $has_bom = $bytes =~ s/\A\Q$BOM\E//;
    my ( $text, $encoding );
    my $copy = $bytes;
    if ( defined( my $decoded = eval { Encode::decode( 'UTF-8', $copy, Encode::FB_CROAK ) } ) ) {
        ( $text, $encoding ) = ( $decoded, 'UTF-8' );
    }
    else {
        ( $text, $encoding ) = ( Encode::decode( 'ISO-8859-1', $bytes ), 'ISO-8859-1' );
    }

    return $class->_new( $text, encoding => $encoding, bom => $has_bom );
}

sub from_string ( $class, $text ) {
    return $class->_new( $text, encoding => 'UTF-8', bom => 0 );
}

sub _new ( $class, $text, %args ) {
    my @line_starts = ( undef, 0 );    # 1-based lines
    while ( $text =~ /\n/g ) {
        push @line_starts, pos $text;
    }
    return bless {
        %args,
        text        => $text,
        line_starts => \@line_starts,
        has_crlf    => ( $text =~ /\r\n/ ? 1 : 0 ),
    }, $class;
}

sub text     ($self) { $self->{text} }
sub has_crlf ($self) { $self->{has_crlf} }
sub encoding ($self) { $self->{encoding} }

sub offset_of_location ( $self, $line, $rowchar ) {
    my $start = $self->{line_starts}[$line];
    die "Line $line is outside the source\n" unless defined $start;
    return $start + $rowchar - 1;
}

sub start_of ( $self, $elem ) {
    my $token = $elem->isa('PPI::Token') ? $elem : $elem->first_token;
    my $loc   = $token->location
        or die "PPI element has no location; call index_locations first\n";
    return $self->offset_of_location( $loc->[0], $loc->[1] );
}

sub end_of ( $self, $elem ) {
    my $token = $elem->isa('PPI::Token') ? $elem : $elem->last_token;
    return $self->start_of($token) + length $token->content;
}

sub encode ( $self, $text ) {
    my $bytes = Encode::encode( $self->{encoding}, $text );
    return $self->{bom} ? $BOM . $bytes : $bytes;
}

sub write_file ( $self, $path, $text ) {
    my $file = path($path);
    my $mode = ( stat "$file" )[2];
    my $tmp  = $file->sibling( '.' . $file->basename . ".puff-$$" );
    $tmp->spew_raw( $self->encode($text) );
    chmod( $mode & 07777, "$tmp" ) if defined $mode;
    rename( "$tmp", "$file" ) or do {
        my $err = $!;
        $tmp->remove;
        die "Cannot write $path: $err\n";
    };
    return;
}

1;

# ABSTRACT: Source text of one file, with offsets for PPI locations

__END__

=pod

=head1 DESCRIPTION

Reads a file, decodes it (UTF-8, falling back to Latin-1), strips a BOM and
maps PPI C<(line, rowchar)> locations to character offsets in the decoded
text. Writing goes back through the original encoding, atomically.

PPI must be given exactly C<< $source->text >> for offsets to line up.

=cut
