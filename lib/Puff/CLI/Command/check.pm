package Puff::CLI::Command::check;

use v5.36;

use Puff::CLI -command;

use Puff::Engine          ();
use Puff::Reporter::JSON  ();
use Puff::Reporter::JSONL ();
use Puff::Reporter::Text  ();
use Puff::Rules           ();
use Puff::Runner          ();
use Time::HiRes           qw( ualarm );

sub abstract    {'lint (and optionally fix) Perl files'}
sub usage_desc  {'%c check %o [paths...]'}
sub description {'Lint the given files and directories (default: .).'}

sub opt_spec {
    return (
        [ 'select=s@',        'enable rules with these codes or prefixes (comma-separated)' ],
        [ 'extend-select=s@', 'enable these rules too (comma-separated)' ],
        [ 'ignore=s@',        'disable these rules (comma-separated)' ],
        [ 'fix',              'apply safe fixes' ],
        [ 'unsafe-fixes!',    'also apply unsafe fixes' ],
        [ 'diff',             'print the fixes as a unified diff; write nothing' ],
        [ 'output-format=s',  'text, json or jsonl', { default => 'text' } ],
        [ 'show-files',       'list the files that would be checked, then exit' ],
        [ 'statistics',       'one line per rule: how many violations and which are fixable' ],
        Puff::CLI->config_opt_spec,
    );
}

sub validate_args ( $self, $opt, $args ) {
    $self->usage_error("--output-format must be text, json or jsonl")
        unless $opt->output_format =~ /\A(?:text|json|jsonl)\z/;
    return;
}

sub execute ( $self, $opt, $args ) {
    my %cli;
    for my $key (qw( select extend_select ignore )) {
        my $given = $opt->$key // next;
        $cli{$key} = [ grep {length} map { split /\s*,\s*/ } @$given ];
    }
    $cli{unsafe_fixes} = $opt->unsafe_fixes if defined $opt->unsafe_fixes;

    my ( $config, $classes ) = Puff::CLI->load_config( $opt, %cli );
    my @rules = Puff::Rules->instantiate(
        $classes,
        select        => $config->select,
        extend_select => $config->extend_select,
        ignore        => $config->ignore,
        rule_options  => $config->rule_options,
    );

    my $mode     = $opt->diff ? 'diff' : $opt->fix ? 'fix' : 'lint';
    my $fix_mode = $config->unsafe_fixes ? 'unsafe' : 'safe';
    my $engine   = Puff::Engine->new( rules => \@rules, fix_mode => $mode eq 'lint' ? 'none' : $fix_mode );
    my $jsonl    = $opt->output_format eq 'jsonl' ? Puff::Reporter::JSONL->new( out => \*STDOUT, mode => $mode ) : undef;
    my $progress = $opt->show_files || $jsonl ? undef : _progress( \*STDERR );
    my $runner   = Puff::Runner->new(
        config   => $config,
        engine   => $engine,
        mode     => $mode,
        progress => $jsonl ? sub ( $done, $total ) { $jsonl->start($total) unless $done } : $progress,
        on_file  => $jsonl ? sub ($result) { $jsonl->file($result) } : undef,
    );
    return _show_files( $runner, $args ) if $opt->show_files;

    my $run = eval { $runner->run(@$args) };
    if ( !$run ) {
        my $error = $@;
        $progress->( 0, 0 ) if $progress;    # stop the timer and erase the line
        # Puff::CLI->main exits 2 when a command dies. The eval keeps a
        # failure inside abort from replacing $error.
        eval { $jsonl->abort( 2, $error ); 1 } if $jsonl;
        die $error;
    }
    my $reporter
        = $jsonl                                            ? $jsonl
        : $opt->output_format eq 'json' && $mode ne 'diff' ? Puff::Reporter::JSON->new
        :   Puff::Reporter::Text->new( fix_mode => $fix_mode, mode => $mode, statistics => $opt->statistics );
    $reporter->report( $run, \*STDOUT, \*STDERR );

    $Puff::CLI::EXIT_CODE = $run->{exit_code};
    return;
}

sub _show_files ( $runner, $args ) {
    my @files = $runner->files(@$args);
    for my $file (@files) {
        if ( ref $file ) {
            print STDERR "$file->{file}: error: $file->{error}\n";
            $Puff::CLI::EXIT_CODE = 2;
        }
        else {
            print "$file\n";
        }
    }
    return;
}

# A progress callback for Puff::Runner that shows a spinner and "Finding
# files", then "Checking 17/250 files", on $fh; undef when $fh is not a
# terminal (or $tty says it is not). A SIGALRM timer redraws it ten times a
# second, so it keeps moving while one large file is parsed. It first draws
# after half a second, so a quick run prints nothing, and it stops and
# erases itself once every file is done.
sub _progress ( $fh, $tty = -t $fh ) {
    return undef unless $tty;
    my $utf8   = ( $ENV{LC_ALL} || $ENV{LC_CTYPE} || $ENV{LANG} || q{} ) =~ /UTF-?8/i;
    my @frames
        = $utf8
        ? split( //, "\x{280b}\x{2819}\x{2839}\x{2838}\x{283c}\x{2834}\x{2826}\x{2827}\x{2807}\x{280f}" )
        : qw( | / - \ );
    my ( $done, $total, $drawn, $frame ) = ( 0, undef, 0, 0 );
    $SIG{ALRM} = sub {
        my $status = defined $total ? "Checking $done/$total files" : 'Finding files';
        printf {$fh} "\r%s %s\e[K", $frames[ $frame++ % @frames ], $status;
        $drawn = 1;
    };
    ualarm( 500_000, 100_000 );
    return sub ( $now_done, $now_total ) {
        ( $done, $total ) = ( $now_done, $now_total );
        return if $done < $total;
        ualarm(0);
        $SIG{ALRM} = 'IGNORE';    # an alarm already on its way must not kill puff
        print {$fh} "\r\e[K" if $drawn;
    };
}

1;

# ABSTRACT: puff check - lint and fix files

__END__

=pod

=head1 DESCRIPTION

Lint the given files and directories (default: .). C<--fix> writes safe
fixes, and unsafe ones too with C<--unsafe-fixes> (or C<unsafe-fixes = true>
in the config). C<--diff> works out the same fixes, prints them as a unified
diff and writes nothing; it wins over C<--fix>. With C<--output-format text>
or C<json> its output is the plain diff; with C<--output-format jsonl> each
file event carries its diff instead (see L<Puff::Reporter::JSONL>).

C<--statistics> prints one line per rule instead of one per violation (see
L<Puff::Reporter::Text>). C<--show-files> prints the files that would be
checked, one per line, and checks nothing: they are plain paths and
C<--statistics> does not apply, whatever C<--output-format> says. While
checking, a spinner and a C<Checking N/M files> counter are shown on STDERR
when it is a terminal and the run takes more than half a second (never with
C<--output-format jsonl>, which streams one JSON object per line as each
file is checked). See
L<Puff::Runner> for exit codes.

=cut
