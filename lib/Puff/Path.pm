package Puff::Path;

use v5.36;

use Encode   ();
use Exporter qw( import );

our @EXPORT_OK = qw( display_name display_lines display_text has_unsafe_text );

# Characters that could move the cursor, start a line or reorder the text
# around them: C0, DEL and C1 controls, Unicode format characters (bidi
# controls, zero-width characters, BOM) and the line and paragraph
# separators.
my $UNSAFE = qr/[\x00-\x1F\x7F\x{80}-\x{9F}\p{Cf}\x{2028}\x{2029}]/;

# A path (bytes, as the filesystem and @ARGV give it) as a character string
# for output.
sub display_name ($path) {
    my $name = $path =~ /[^\x00-\xFF]/
        ? $path    # already characters
        : Encode::decode( 'UTF-8', $path, Encode::FB_PERLQQ | Encode::LEAVE_SRC );
    return _escape($name);
}

# Controls become \xHH, like an invalid byte; the rest (U+00AD, the soft
# hyphen, among them) become \x{HHHH}.
sub _escape ($chars) {
    return $chars =~ s/($UNSAFE)/_escape_char(ord $1)/ger;
}

sub _escape_char ($ord) {
    return $ord < 0xA0 ? sprintf( '\\x%02X', $ord ) : sprintf( '\\x{%04X}', $ord );
}

# Multi-line text (an error or warning from perl, say) with each line shown
# like a path, so the newlines survive.
sub display_lines ($text) {
    return join "\n", map { display_name($_) } split /\n/, $text, -1;
}

# Like display_lines, for text that is already characters (a violation
# message, a TOML key): nothing is decoded.
sub display_text ($text) {
    return join "\n", map { _escape($_) } split /\n/, $text, -1;
}

# Whether $text holds a character the functions above would escape, other
# than a tab or newline.
sub has_unsafe_text ($text) {
    return $text =~ /(?![\t\n])$UNSAFE/ ? 1 : 0;
}

1;

# ABSTRACT: Show a file path as text

__END__

=pod

=head1 SYNOPSIS

    use Puff::Path qw( display_name display_lines display_text );

    print display_name($path), "\n";
    print display_lines($message);
    print display_text( $violation->message );

=head1 DESCRIPTION

C<display_name($path)> turns a path, which is a byte string as the
filesystem and C<@ARGV> give it, into a character string for output. The
bytes are decoded as UTF-8; a byte that is not part of valid UTF-8 is shown
as a C<\xHH> escape, so a Latin-1 C<caf\xE9.pl> is shown as the literal text
C<caf\xE9.pl>. Control characters (C<\x00> to C<\x1F>, C<\x7F> and C<\x80>
to C<\x9F>) are escaped the same way, so a file name cannot move the cursor
or start a new output line. Unicode format characters (C<\p{Cf}>: the bidi
controls U+202A to U+202E and U+2066 to U+2069, zero-width characters, the
BOM and the soft hyphen) and the separators U+2028 and U+2029 are shown as
C<\x{HHHH}>, so a name cannot reorder or hide the text around it. Other
non-ASCII characters, such as C<E<eacute>> or CJK, are shown as they are. A
backslash is left alone, so a name that really contains C<\xE9> looks the
same as one with that byte, and escaping is not idempotent: escape a string
once, just before it is shown.

It takes byte paths. A string with a character above C<\xFF> is taken to
be decoded already and only has its control characters escaped (decoding
it would fail), but a character string whose non-ASCII characters are all
in C<\x80> to C<\xFF> cannot be told from bytes and is misread: encode it
to UTF-8 first. The result is for showing only, and escaping loses
information: open files by the original path.

C<display_lines($text)> does the same for text of several lines, such as
an error message from perl that contains a path. Each line is treated as
C<display_name> treats a path, and the newlines between lines are kept, so
a trailing newline stays. Like C<display_name> it takes bytes; callers must
stringify an object, such as an exception, before passing it in.

C<display_text($text)> is C<display_lines> for text that is already a
character string, such as a violation message or a key from the config
file: it escapes the same characters but decodes nothing, so a Latin-1
character such as C<E<eacute>> stays as it is.

C<has_unsafe_text($text)> is true when C<$text>, a character string, holds
a character these functions escape other than a tab or a newline. It is
for text that is printed as it is, such as a diff.

=cut
