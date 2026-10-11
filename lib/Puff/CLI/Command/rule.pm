package Puff::CLI::Command::rule;

use v5.36;

use Puff::CLI -command;

use Puff::Path qw( display_name );

sub abstract   {'explain one rule'}
sub usage_desc {'%c rule %o CODE'}
sub opt_spec   { Puff::CLI->config_opt_spec }

sub validate_args ( $self, $opt, $args ) {
    $self->usage_error("rule takes exactly one rule code") unless @$args == 1;
    return;
}

sub execute ( $self, $opt, $args ) {
    my ($code) = @$args;
    my ( undef, $classes ) = Puff::CLI->load_config($opt);
    my ($info) = grep { $_->{code} eq $code } Puff::CLI->rule_info($classes);
    die 'Unknown rule ' . display_name($code) . "\n" unless $info;

    print "$info->{code}: $info->{summary}\n";
    print "Fix safety: $info->{fix_safety}\n";
    print 'CWE: ', join( ', ', map {"CWE-$_"} @{ $info->{cwe} } ), "\n" if @{ $info->{cwe} };
    if ( $info->{class} && length( my $text = $info->{class}->explanation ) ) {
        print "\n$text";
        print "\n" unless $text =~ /\n\z/;
    }
    return;
}

1;

# ABSTRACT: puff rule - explain one rule

__END__

=pod

=head1 DESCRIPTION

Prints the rule's code, summary, fix safety, CWE ids (if any) and
explanation.

=cut
