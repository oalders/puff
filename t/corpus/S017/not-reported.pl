use v5.36;

sub html_escape ($text) {
    $text =~ s/&/&amp;/g;
    $text =~ s/</&lt;/g;
    $text =~ s/>/&gt;/g;
    $text =~ s/"/&quot;/g;
    $text =~ s/'/&#39;/g;
    return $text;
}

# Text content only: " is not escaped, so this is not an attribute escaper.
sub text_escape ($text) {
    $text =~ s/&/&amp;/g;
    $text =~ s/</&lt;/g;
    return $text;
}

my %ESCAPE = ( '&' => '&amp;', '<' => '&lt;', '"' => '&quot;', q{'} => '&#39;' );

sub escape_table ($text) {
    $text =~ s/([&<>"'])/$ESCAPE{$1}/g;
    return $text;
}

sub escape_hex ($text) {
    $text =~ s/([&<"\x27])/'&#' . ord($1) . ';'/ge;
    return $text;
}

# Only " is escaped, for a CSV-ish purpose with no < rule.
sub quote_only ($text) {
    $text =~ s/"/&quot;/g;
    return $text;
}

# The < and " rules are in different subs.
sub lt_only ($text) { $text =~ s/</&lt;/g; return $text }

# Escapes for cmd.exe, not HTML.
sub cmd_quote ($text) {
    $text =~ s/([()%!^"<>&|])/^$1/g;
    return $text;
}
