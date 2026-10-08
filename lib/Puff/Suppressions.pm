package Puff::Suppressions;

use v5.36;

my $MESSAGE = 'suppression comment must list codes';

sub new ( $class, $doc ) {
    $doc->index_locations;
    my ( %line, @file, @problems );
    my $comments = $doc->find('PPI::Token::Comment') || [];
    for my $comment (@$comments) {
        my ( $line, $column ) = @{ $comment->location };

        # PPI merges consecutive own-line comments into one token
        for my $text ( split /\n/, $comment->content ) {
            if ( $text =~ /\A(\s*)\#\s*puff:\s*(ignore-file|ignore)\b(.*)\z/ ) {
                my ( $indent, $kind, $rest ) = ( $1, $2, $3 );
                my @codes = grep { length } split /[\s,]+/, $rest;
                if ( !@codes ) {
                    push @problems, { line => $line, column => $column + length($indent), message => $MESSAGE };
                }
                elsif ( $kind eq 'ignore-file' ) { push @file, @codes }
                else                             { push @{ $line{$line} }, @codes }
            }
            $line++;
            $column = 1;
        }
    }
    return bless { line => \%line, file => \@file, problems => \@problems }, $class;
}

sub is_suppressed ( $self, $code, $line ) {
    for my $prefix ( @{ $self->{file} }, @{ $self->{line}{$line} // [] } ) {
        return 1 if index( $code, $prefix ) == 0;
    }
    return 0;
}

sub problems ($self) { return $self->{problems} }

1;

# ABSTRACT: Parse "# puff: ignore" suppression comments

__END__

=pod

=head1 DESCRIPTION

Collects C<# puff: ignore CODES> (this line) and C<# puff: ignore-file CODES>
(whole file) from C<PPI::Token::Comment> tokens only. Codes are prefixes. A
bare comment with no codes suppresses nothing and is returned by C<problems>
for reporting as P001.

=cut
