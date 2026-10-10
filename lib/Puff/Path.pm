package Puff::Path;

use v5.36;

use Encode   ();
use Exporter qw( import );

our @EXPORT_OK = qw( display_name );

# A path (bytes, as the filesystem and @ARGV give it) as a character string
# for output.
sub display_name ($path) {
    my $name = $path =~ /[^\x00-\xFF]/
        ? $path    # already characters
        : Encode::decode( 'UTF-8', $path, Encode::FB_PERLQQ | Encode::LEAVE_SRC );
    return $name =~ s/([\x00-\x1F\x7F\x{80}-\x{9F}])/sprintf '\\x%02X', ord $1/ger;
}

1;

# ABSTRACT: Show a file path as text

__END__

=pod

=head1 SYNOPSIS

    use Puff::Path qw( display_name );

    print display_name($path), "\n";

=head1 DESCRIPTION

C<display_name($path)> turns a path, which is a byte string as the
filesystem and C<@ARGV> give it, into a character string for output. The
bytes are decoded as UTF-8; a byte that is not part of valid UTF-8 is shown
as a C<\xHH> escape, so a Latin-1 C<caf\xE9.pl> is shown as the literal text
C<caf\xE9.pl>. Control characters (C<\x00> to C<\x1F>, C<\x7F> and C<\x80>
to C<\x9F>) are escaped the same way, so a file name cannot move the cursor
or start a new output line. A backslash is left alone, so a name that
really contains C<\xE9> looks the same as one with that byte.

It takes byte paths. A string with a character above C<\xFF> is taken to
be decoded already and only has its control characters escaped (decoding
it would fail), but a character string whose non-ASCII characters are all
in C<\x80> to C<\xFF> cannot be told from bytes and is misread: encode it
to UTF-8 first. The result is for showing only, and escaping loses
information: open files by the original path.

=cut
