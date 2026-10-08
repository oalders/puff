use v5.36;
use Test2::V0;

use Cwd          qw( getcwd );
use Path::Tiny   qw( path tempdir );
use Puff::Config ();
use Puff::Engine ();
use Puff::Runner ();

package FlagWord {    # flags and fixes the bareword "foo"
    use v5.36;
    use parent 'Puff::Rule';
    sub code       {'T001'}
    sub applies_to {'PPI::Token::Word'}
    sub fix_safety {'safe'}

    sub check ( $self, $elem, $doc ) {
        return unless $elem->content eq 'foo';
        return $self->violation( $elem, message => 'foo' );
    }

    sub fix ( $self, $violation, $fix ) {
        $fix->replace( $violation->element, 'bar' );
        return 1;
    }
}

package DyingEngine {    # dies for any file whose name contains "bad"
    use v5.36;
    use parent -norequire, 'Puff::Engine';

    sub process_source ( $self, $src, %args ) {
        die "engine exploded\n" if $args{file} =~ /bad/;
        return $self->SUPER::process_source( $src, %args );
    }
}

package main;

my $config = Puff::Config->load( no_config => 1 );

sub runner ( $mode, $engine_class = 'Puff::Engine' ) {
    return Puff::Runner->new(
        config => $config,
        engine => $engine_class->new( rules => [ FlagWord->new ], fix_mode => $mode eq 'lint' ? 'none' : 'safe' ),
        mode   => $mode,
    );
}

my $dir = tempdir();
$dir->child('bad.pl')->spew_utf8("foo;\n");
$dir->child('good.pl')->spew_utf8("foo;\n");

subtest 'an engine exception is an error for that file only' => sub {
    my $run = runner( 'lint', 'DyingEngine' )->run( map { $dir->child($_)->stringify } qw( bad.pl good.pl ) );
    my %by  = map { path( $_->{file} )->basename => $_ } @{ $run->{files} };
    is( $by{'bad.pl'}{error}, 'engine exploded', 'error recorded for the failing file' );
    is( scalar @{ $by{'good.pl'}{violations} }, 1, 'other file still processed' );
    is( $run->{exit_code}, 2, 'exit 2' );
};

subtest 'a file named twice is processed once' => sub {
    my $orig = getcwd;
    chdir "$dir" or die "chdir: $!";
    my $abs = path('good.pl')->absolute->stringify;
    my $run = runner('lint')->run( 'good.pl', $abs, './good.pl' );
    chdir $orig or die "chdir: $!";
    is( [ map { $_->{file} } @{ $run->{files} } ], ['good.pl'], 'one entry, as first named' );
};

subtest 'a file found twice via a directory and by name is processed once' => sub {
    my $run = runner('lint')->run( "$dir", $dir->child('good.pl')->stringify );
    is( scalar( grep { $_->{file} =~ /good\.pl\z/ } @{ $run->{files} } ), 1, 'good.pl once' );
};

subtest 'diff headers for an absolute path' => sub {
    my $run  = runner('diff')->run( $dir->child('good.pl')->stringify );
    my $diff = $run->{files}[0]{diff};
    my $rel  = $dir->child('good.pl')->stringify =~ s{\A/+}{}r;
    like( $diff, qr{^--- a/\Q$rel\E}m,  'a/ header has no double slash' );
    like( $diff, qr{^\+\+\+ b/\Q$rel\E}m, 'b/ header has no double slash' );
};

done_testing;
