package Puff::CLI;

use v5.36;

use App::Cmd::Setup -app;

use Puff::Config ();
use Puff::Engine ();
use Puff::Rules  ();

our $EXIT_CODE = 0;

sub main ($class) {
    # :utf8 rather than :encoding(UTF-8): the encoding layer drops write
    # errors (such as a full disk) for all but the last buffer, so the
    # reporters could not tell that output was lost.
    binmode STDOUT, ':utf8';
    binmode STDERR, ':utf8';
    local $EXIT_CODE = 0;
    my $ok = eval { $class->run; 1 };
    my $error = $@;

    if ( !$ok ) {
        print STDERR $error =~ /\n\z/ ? $error : "$error\n";
        return 2;
    }
    return $EXIT_CODE;
}

# App::Cmd prints an unknown command's usage to STDOUT and exits 1 from an
# END block; puff treats it as a usage error (STDERR, exit 2) instead.
sub get_command ( $self, @args ) {
    my ( $cmd, $opt, @rest ) = $self->SUPER::get_command(@args);
    die "Unrecognized command: $cmd\n" if defined $cmd && !$self->plugin_for($cmd);
    return ( $cmd, $opt, @rest );
}

sub config_opt_spec ($class) {
    return (
        [ 'config=s',  'read this config file instead of ./.puff.toml' ],
        [ 'no-config', 'ignore config files' ],
    );
}

# Loads the config and every rule class; dies on any error.
sub load_config ( $class, $opt, %cli ) {
    my $config = Puff::Config->load( path => $opt->config, no_config => $opt->no_config, cli => \%cli );
    my @classes = Puff::Rules->load( rule_paths => $config->rule_paths );
    return ( $config, \@classes );
}

sub rule_info ( $class, $classes ) {
    return (
        ( map { { code => $_->code, summary => $_->summary, fix_safety => $_->fix_safety, cwe => [ $_->cwe ], class => $_ } } @$classes ),
        ( map { { %$_, fix_safety => 'none', cwe => [] } } Puff::Engine->builtin_rules_info ),
    );
}

1;

# ABSTRACT: The puff command-line application

__END__

=pod

=head1 SYNOPSIS

    exit Puff::CLI->main;

=head1 DESCRIPTION

An L<App::Cmd> application with the commands C<check>, C<rule> and C<rules>.
C<main> runs it and returns the exit code: the command's
C<$Puff::CLI::EXIT_CODE>, or 2 for any usage, config, rule-loading or
internal error, whose message goes to STDERR.

=cut
