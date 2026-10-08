use v5.36;

sub html_escape ($text) {
    $text =~ s/&/&amp;/g;
    $text =~ s/</&lt;/g;
    $text =~ s/>/&gt;/g;
    $text =~ s/"/&quot;/g;    # expect: S017
    $text =~ s/'/&#39;/g;
    return $text;
}

sub escape_topic {
    local $_ = shift;
    s{&}{&amp;}g;
    s{<}{&lt;}g;
    s{\"}{&#34;}g;    # expect: S017
    s{'}{&#39;}g;
    return $_;
}

sub escape_r ($text) {
    return $text =~ s/&/&amp;/gr =~ s/</&lt;/gr =~ s/"/&quot;/gr =~ s/'/&#39;/gr;    # expect: S017
}

my %ESCAPE = ( '&' => '&amp;', '<' => '&lt;', '>' => '&gt;', '"' => '&quot;' );

sub escape_table ($text) {
    $text =~ s/([&<>"])/$ESCAPE{$1}/g;    # expect: S017
    return $text;
}

my $title = shift // q{};
$title =~ s/&/&amp;/g;
$title =~ s/</&lt;/g;
$title =~ s/"/&quot;/g;    # expect: S017
$title =~ s/'/&#39;/g;
print qq{<a title='$title'>x</a>\n};
