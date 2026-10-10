use v5.36;
use Test2::V0;

use Puff::Path qw( display_name );

subtest 'display_name' => sub {
    is( display_name('lib/Foo.pm'), 'lib/Foo.pm', 'ASCII unchanged' );
    is( display_name("caf\xc3\xa9.pl"), "caf\x{e9}.pl", 'UTF-8 decoded' );
    is( display_name("caf\xe9\xc3\xa9"), "caf\\xE9\x{e9}", 'invalid bytes escaped' );
    is( display_name("a\e[31mb.pl"), 'a\x1B[31mb.pl', 'ESC escaped' );
    is( display_name("a\nb.pl"), 'a\x0Ab.pl', 'newline escaped' );
    is( display_name("a\x7f\xc2\x9b.pl"), 'a\x7F\x9B.pl', 'DEL and C1 escaped' );
    is( display_name('a\b.pl'), 'a\b.pl', 'backslash left alone' );
    is( display_name("\x{263a}\x{e9}\n"), "\x{263a}\x{e9}\\x0A", 'characters are not decoded again' );
    my $bytes = "caf\xe9.pl";
    display_name($bytes);
    is( $bytes, "caf\xe9.pl", 'argument left alone' );
};

done_testing;
