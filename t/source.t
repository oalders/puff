use v5.36;
use Test2::V0;

use Path::Tiny qw( tempdir );
use PPI        ();
use Puff::Source ();

my @docs;    # PPI drops token locations when a document is destroyed

sub first_word ( $src, $content ) {
    my $doc = PPI::Document->new( \( $src->text ) );
    push @docs, $doc;
    $doc->index_locations;
    return $doc->find_first(
        sub { $_[1]->isa('PPI::Token::Word') && $_[1]->content eq $content }
    );
}

sub word_maps_to_itself ( $src, $content, $name ) {
    my $word = first_word( $src, $content );
    ok( $word, "$name: found $content" ) or return;
    is(
        substr( $src->text, $src->start_of($word), length $content ),
        $content, "$name: start_of points at $content"
    );
}

subtest 'offset_of_location' => sub {
    my $src = Puff::Source->from_string("my \$x = 1;\nrand();\n");
    is( $src->offset_of_location( 1, 1 ), 0,  'line 1 col 1' );
    is( $src->offset_of_location( 2, 1 ), 11, 'line 2 col 1' );
    ok( !$src->has_cr, 'no CR' );
};

subtest 'heredoc, POD, __END__ and __DATA__' => sub {
    word_maps_to_itself(
        Puff::Source->from_string("print <<EOT;\nhello\nEOT\nrand();\n"),
        'rand', 'heredoc'
    );
    word_maps_to_itself(
        Puff::Source->from_string(
            "print <<~EOT, <<'B';\n  x\n  EOT\nb\nB\nmy \$y = rand();\n"),
        'rand', 'two heredocs'
    );
    word_maps_to_itself(
        Puff::Source->from_string(
            "=pod\n\nhello\n\n=cut\n\nrand();\n__END__\nrand\n"),
        'rand', 'pod and __END__'
    );
    word_maps_to_itself(
        Puff::Source->from_string("rand();\n__DATA__\nrand\n"),
        'rand', '__DATA__'
    );
};

subtest 'end_of' => sub {
    my $src = Puff::Source->from_string("foo(1, 2); bar();\n");
    my $doc = PPI::Document->new( \( $src->text ) );
    $doc->index_locations;
    my $stmt = $doc->child(0);
    is( $src->start_of($stmt), 0,  'statement start' );
    is( $src->end_of($stmt),   10, 'statement end is after the semicolon' );
};

my $dir = tempdir();

subtest 'UTF-8 files' => sub {
    my $file = $dir->child('utf8.pl');
    $file->spew_raw(qq{my \$s = "\xC3\xA9\xE2\x82\xAC"; rand();\n});
    my $src = Puff::Source->from_file("$file");
    is( length( $src->text ), 22, 'text is decoded to characters' );
    word_maps_to_itself( $src, 'rand', 'utf8' );
    my $word = first_word( $src, 'rand' );
    is( $word->location->[1], 15, 'PPI column counts characters' );
    is( $src->encode( $src->text ), $file->slurp_raw, 'round trip' );
};

subtest 'BOM' => sub {
    my $file = $dir->child('bom.pl');
    $file->spew_raw("\xEF\xBB\xBFrand();\n");
    my $src = Puff::Source->from_file("$file");
    is( $src->text, "rand();\n", 'BOM stripped' );
    is( $src->encode( $src->text ), $file->slurp_raw, 'BOM restored' );
};

subtest 'Latin-1 fallback' => sub {
    my $file = $dir->child('latin1.pl');
    $file->spew_raw(qq{my \$s = "\xE9"; rand();\n});
    my $src = Puff::Source->from_file("$file");
    is( $src->text, qq{my \$s = "\x{e9}"; rand();\n}, 'decoded as Latin-1' );
    word_maps_to_itself( $src, 'rand', 'latin1' );
    is( $src->encode( $src->text ), $file->slurp_raw, 'round trip' );
};

subtest 'carriage returns' => sub {
    ok( Puff::Source->from_string("a;\r\nb;\r\n")->has_cr, 'CRLF detected' );
    ok( Puff::Source->from_string("a;\rb;\r")->has_cr,       'lone CR detected' );
    ok( Puff::Source->from_string("a; # x\ry\nb;\n")->has_cr, 'CR inside a line detected' );
};

subtest 'write_file' => sub {
    my $file = $dir->child('script.pl');
    $file->spew_raw(qq{print "\xC3\xA9";\n});
    chmod 0755, "$file";
    my $src = Puff::Source->from_file("$file");
    $src->write_file( "$file", qq{say "\x{e9}";\n} );
    is( $file->slurp_raw, qq{say "\xC3\xA9";\n}, 'written in original encoding' );
    is( ( stat "$file" )[2] & 07777, 0755, 'mode preserved' );
};

subtest 'write_file follows a symlink' => sub {
    my $real = $dir->child('real.pl');
    my $link = $dir->child('link.pl');
    $real->spew_raw("a;\n");
    symlink( "$real", "$link" ) or skip_all "cannot symlink: $!";
    my $src = Puff::Source->from_file("$link");
    $src->write_file( "$link", "b;\n" );
    ok( -l "$link", 'link is still a symlink' );
    is( readlink("$link"), "$real", 'link target unchanged' );
    is( $real->slurp_raw, "b;\n", 'target file written' );
};

subtest 'unencodable text' => sub {
    my $file = $dir->child('latin1-write.pl');
    $file->spew_raw(qq{my \$s = "\xE9";\n});
    my $src = Puff::Source->from_file("$file");
    like(
        dies { $src->encode(qq{my \$s = "\x{20ac}";\n}) },
        qr/ISO-8859-1/, 'encode dies for a character the encoding lacks'
    );
    ok( dies { $src->write_file( "$file", qq{my \$s = "\x{20ac}";\n} ) }, 'write_file dies' );
    is( $file->slurp_raw, qq{my \$s = "\xE9";\n}, 'file unchanged' );
    is( [ grep {/\.puff-/} map { $_->basename } $dir->children ], [], 'no temp file left' );
};

subtest 'read errors' => sub {
    like(
        dies { Puff::Source->from_file( $dir->child('nope.pl') . q{} ) },
        qr/nope\.pl/, 'missing file dies with its name'
    );
};

done_testing;
