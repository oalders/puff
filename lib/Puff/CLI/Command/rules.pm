package Puff::CLI::Command::rules;

use v5.36;

use Puff::CLI -command;

sub abstract   {'list every rule'}
sub usage_desc {'%c rules %o'}
sub opt_spec   { Puff::CLI->config_opt_spec }

sub validate_args ( $self, $opt, $args ) {
    $self->usage_error("rules takes no arguments") if @$args;
    return;
}

sub execute ( $self, $opt, $args ) {
    my ( undef, $classes ) = Puff::CLI->load_config($opt);
    printf "%-6s %-7s %s\n", @{$_}{qw( code fix_safety summary )} for Puff::CLI->rule_info($classes);
    return;
}

1;

# ABSTRACT: puff rules - list every rule

__END__

=pod

=head1 DESCRIPTION

Lists every loaded rule (code, fix safety and summary), plus the built-in
P001.

=cut
