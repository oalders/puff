package Puff::CLI::Command::check;

use v5.36;

use Puff::CLI -command;

use Puff::Engine         ();
use Puff::Reporter::JSON ();
use Puff::Reporter::Text ();
use Puff::Rules          ();
use Puff::Runner         ();
use Time::HiRes          qw( time );

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
        [ 'output-format=s',  'text or json', { default => 'text' } ],
        [ 'show-files',       'list the files that would be checked, then exit' ],
        Puff::CLI->config_opt_spec,
    );
}

sub validate_args ( $self, $opt, $args ) {
    $self->usage_error("--output-format must be text or json")
        unless $opt->output_format =~ /\A(?:text|json)\z/;
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
    my $runner   = Puff::Runner->new(
        config   => $config,
        engine   => $engine,
        mode     => $mode,
        progress => _progress( \*STDERR ),
    );
    return _show_files( $runner, $args ) if $opt->show_files;

    my $run = $runner->run(@$args);
    my $reporter
        = $opt->output_format eq 'json' && $mode ne 'diff'
        ? Puff::Reporter::JSON->new
        : Puff::Reporter::Text->new( fix_mode => $fix_mode, mode => $mode );
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

# A progress callback that shows "Checking 17/250 files" on $fh, or undef
# when $fh is not a terminal (or $tty says it is not). It stays quiet for
# the first half second, so a quick run prints nothing, redraws at most ten
# times a second, and erases itself after the last file.
sub _progress ( $fh, $tty = -t $fh ) {
    return undef unless $tty;
    my $start = time;
    my $drawn = 0;
    return sub ( $done, $total ) {
        my $now = time;
        if ( $done == $total ) {
            print {$fh} "\r\e[K" if $drawn;
            return;
        }
        return if $now - $start < 0.5 || $now - $drawn < 0.1;
        $drawn = $now;
        printf {$fh} "\rChecking %d/%d files", $done, $total;
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
diff and writes nothing; it wins over C<--fix>, and its output is always the
diff, whatever C<--output-format> says.

C<--show-files> prints the files that would be checked, one per line, and
checks nothing. While checking, a C<Checking N/M files> counter is shown on
STDERR when it is a terminal and the run takes more than half a second.
See L<Puff::Runner> for exit codes.

=cut
