use v5.36;
use Test2::V0;

use Encode ();

use Puff::Path qw( display_lines display_name display_text has_unsafe_text );

subtest 'display_name' => sub {
    is( display_name('lib/Foo.pm'), 'lib/Foo.pm', 'ASCII unchanged' );
    is( display_name("caf\xc3\xa9.pl"), "caf\x{e9}.pl", 'UTF-8 decoded' );
    is( display_name("caf\xe9\xc3\xa9"), "caf\\xE9\x{e9}", 'invalid bytes escaped' );
    is( display_name("a\e[31mb.pl"), 'a\x1B[31mb.pl', 'ESC escaped' );
    is( display_name("a\nb.pl"), 'a\x0Ab.pl', 'newline escaped' );
    is( display_name("a\x7f\xc2\x9b.pl"), 'a\x7F\x9B.pl', 'DEL and C1 escaped' );
    is( display_name('a\b.pl'), 'a\b.pl', 'backslash left alone' );
    is( display_name("\x{263a}\x{e9}\n"), "\x{263a}\x{e9}\\x0A", 'characters are not decoded again' );
    is( display_name("a\xe2\x80\xaeb.pl"), 'a\x{202E}b.pl', 'bidi override escaped' );
    is(
        display_name( Encode::encode_utf8("\x{2066}\x{200b}\x{feff}\x{ad}\x{2028}\x{2029}\x{e0001}") ),
        '\x{2066}\x{200B}\x{FEFF}\x{00AD}\x{2028}\x{2029}\x{E0001}',
        'format characters and separators escaped as \x{HHHH}'
    );
    is( display_name("\x{4e2d}\x{6587}.pl"), "\x{4e2d}\x{6587}.pl", 'CJK as is' );
    my $bytes = "caf\xe9.pl";
    display_name($bytes);
    is( $bytes, "caf\xe9.pl", 'argument left alone' );
};

subtest 'display_lines' => sub {
    is( display_lines(''), '', 'empty' );
    is( display_lines("a\n"), "a\n", 'trailing newline kept' );
    is( display_lines("a\n\nb"), "a\n\nb", 'empty line kept' );
    is( display_lines("\r"), '\x0D', 'lone CR escaped' );
    is( display_lines("a\nb\ec\nd"), "a\nb\\x1Bc\nd", 'control character escaped on one line of several' );
    is( display_lines("caf\xe9\ncaf\xc3\xa9\n"), "caf\\xE9\ncaf\x{e9}\n", 'invalid UTF-8 escaped, valid decoded' );
};

subtest 'display_text' => sub {
    is( display_text("caf\x{e9}\n"), "caf\x{e9}\n", 'Latin-1 characters not decoded' );
    is( display_text("a\e[2J\x{202e}\nb\r"), "a\\x1B[2J\\x{202E}\nb\\x0D", 'controls and bidi escaped, newline kept' );
};

subtest 'has_unsafe_text' => sub {
    ok( !has_unsafe_text("caf\x{e9}\tx\n"), 'tab, newline and letters are safe' );
    ok( has_unsafe_text($_), sprintf 'U+%04X is unsafe', ord ) for "\e", "\r", "\x{202e}", "\x{200b}", "\x{2028}";
};

done_testing;
