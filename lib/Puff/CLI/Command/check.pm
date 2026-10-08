package Puff::CLI::Command::check;

use v5.36;

use Puff::CLI -command;

use Puff::Engine         ();
use Puff::Reporter::JSON ();
use Puff::Reporter::Text ();
use Puff::Rules          ();
use Puff::Runner         ();

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

    my $mode       = $opt->diff ? 'diff' : $opt->fix ? 'fix' : 'lint';
    my $fix_mode   = $config->unsafe_fixes ? 'unsafe' : 'safe';
    my $engine     = Puff::Engine->new( rules => \@rules, fix_mode => $mode eq 'lint' ? 'none' : $fix_mode );
    my $run        = Puff::Runner->new( config => $config, engine => $engine, mode => $mode )->run(@$args);
    my $reporter
        = $opt->output_format eq 'json' && $mode ne 'diff'
        ? Puff::Reporter::JSON->new
        : Puff::Reporter::Text->new( fix_mode => $fix_mode, mode => $mode );
    $reporter->report( $run, \*STDOUT, \*STDERR );

    $Puff::CLI::EXIT_CODE = $run->{exit_code};
    return;
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
diff, whatever C<--output-format> says. See L<Puff::Runner> for exit codes.

=cut
