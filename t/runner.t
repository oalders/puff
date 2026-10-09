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

subtest 'progress' => sub {
    $dir->child('one.pl')->spew_utf8("foo;\n");
    $dir->child('two.pl')->spew_utf8("1;\n");
    my @calls;
    my $runner = Puff::Runner->new(
        config   => $config,
        engine   => Puff::Engine->new( rules => [ FlagWord->new ], fix_mode => 'none' ),
        progress => sub (@args) { push @calls, \@args },
    );
    is( [ $runner->files("$dir") ], [ map { $dir->child($_)->stringify } qw( one.pl two.pl ) ], 'files' );
    $runner->run("$dir");
    is( \@calls, [ [ 0, 2 ], [ 1, 2 ], [ 2, 2 ] ], 'called once the files are found, then after each one' );
    $dir->child($_)->remove for qw( one.pl two.pl );
};
subtest 'on_file' => sub {
    $dir->child('one.pl')->spew_utf8("foo;\n");
    $dir->child('two.pl')->spew_utf8("1;\n");
    my @events;
    my $runner = Puff::Runner->new(
        config   => $config,
        engine   => Puff::Engine->new( rules => [ FlagWord->new ], fix_mode => 'none' ),
        on_file  => sub ($result) { push @events, [ file => $result ] },
        progress => sub ( $done, $total ) { push @events, [ progress => $done ] },
    );
    my $missing = $dir->child('missing.pl')->stringify;
    my $run     = $runner->run( $dir->child('two.pl')->stringify, $missing, $dir->child('one.pl')->stringify );
    is(
        [ map { $_->[0] eq 'file' ? 'file' : "progress $_->[1]" } @events ],
        [ 'progress 0', 'file', 'progress 1', 'file', 'progress 2', 'file', 'progress 3' ],
        'called once per file, before progress'
    );
    my @results = map { $_->[1] } grep { $_->[0] eq 'file' } @events;
    is( [ map { path( $_->{file} )->basename } @results ], [qw( two.pl missing.pl one.pl )], 'in order' );
    ref_is( $results[$_], $run->{files}[$_], "result $_ is the run's entry" ) for 0 .. 2;
    is( $results[1], { file => $missing, error => 'No such file or directory' }, 'missing path entry' );
    is( scalar @{ $results[2]{violations} }, 1, 'violations included' );
    $dir->child($_)->remove for qw( one.pl two.pl );
};
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
    like( $diff, qr{^--- a/\Q$rel\E}m, 'a/ header has no double slash' );
    like( $diff, qr{^\+\+\+ b/\Q$rel\E}m, 'b/ header has no double slash' );
};

subtest 'extensionless files with a perl shebang are found' => sub {
    my $tree = tempdir();
    $tree->child('bin')->mkpath;
    my %files = (
        'tool'       => "#!/usr/bin/env perl\nfoo;\n",
        'tool-args'  => "#!/usr/bin/env -S perl -w\nfoo;\n",
        'tool-perl'  => "#!/usr/bin/perl -w\nfoo;\n",
        'tool-perl5' => "#! /opt/perl/bin/perl5.36.0\nfoo;\n",
        'sh-tool'    => "#!/bin/sh\nfoo;\n",
        'env-sh'     => "#!/usr/bin/env bash\nperl foo;\n",
        'perlish'    => "#!/usr/bin/perlbrew-wrapper\nfoo;\n",
        'notperl'    => "#!/usr/bin/superperl\nfoo;\n",
        'no-shebang' => "foo;\n",
        'late'       => "\n#!/usr/bin/perl\nfoo;\n",
        'binary'     => "\x7fELF\x00\x01perl\x00",
        'empty'      => '',
        'script.sh'  => "#!/usr/bin/perl\nfoo;\n",
        'long'       => '#!/' . ( 'x' x 300 ) . "/perl\nfoo;\n",    # only 256 bytes are read
    );
    $tree->child( 'bin', $_ )->spew_raw( $files{$_} ) for keys %files;
    $tree->child( 'bin', 'unreadable' )->spew_raw("#!/usr/bin/perl\nfoo;\n");
    chmod 0000, $tree->child( 'bin', 'unreadable' );
    # root (as in CI containers) reads mode 0000 files, so the file would be
    # linted; there the unreadable case cannot be tested and is dropped
    $tree->child( 'bin', 'unreadable' )->remove if -r $tree->child( 'bin', 'unreadable' );
    require POSIX;
    POSIX::mkfifo( $tree->child( 'bin', 'fifo' )->stringify, 0600 ) or die "mkfifo: $!";    # must not block

    my @found = map { path($_)->basename } runner('lint')->_find($tree);
    my @want  = sort qw( tool tool-args tool-perl tool-perl5 perlish );
    is( [ sort @found ], \@want, 'only perl shebangs are picked up' );

    my $run = runner('lint')->run("$tree");
    is( $run->{exit_code}, 1, 'found files are linted (exit 1), unreadable and binary skipped silently' );
    is( [ grep { defined $_->{error} } @{ $run->{files} } ], [], 'no errors' );
    chmod 0600, $tree->child( 'bin', 'unreadable' ) if $tree->child( 'bin', 'unreadable' )->exists;
};

done_testing;
