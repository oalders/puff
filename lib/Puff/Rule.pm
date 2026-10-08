package Puff::Rule;

use v5.36;

use Puff::Violation ();

sub new ( $class, %args ) {
    return bless { options => $args{options} // {} }, $class;
}

sub code        {''}
sub summary     {''}
sub explanation {''}
sub applies_to  {'PPI::Element'}
sub fix_safety  {'none'}
sub options     { {} }

sub check ( $self, $elem, $doc ) { return }
sub fix ( $self, $violation, $fix ) { return 0 }

sub option ( $self, $name ) {
    my $configured = $self->{options};
    return $configured->{$name} if exists $configured->{$name};
    return $self->options->{$name};
}

sub violation ( $self, $elem, %args ) {
    my $loc = $elem->location or die "PPI element has no location\n";
    my $fixable = $self->fix_safety eq 'none' ? 0 : ( $args{fixable} // 1 );
    return Puff::Violation->new(
        rule    => $self,
        code    => $self->code,
        element => $elem,
        line    => $loc->[0],
        column  => $loc->[1],
        message => $args{message},
        fixable => $fixable ? 1 : 0,
    );
}

1;

# ABSTRACT: Base class for puff rules

__END__

=pod

=head1 SYNOPSIS

    package Puff::Rule::Security::TwoArgOpen;
    use v5.36;
    use parent 'Puff::Rule';

    sub code       {'S002'}
    sub summary    {'Use three-argument open'}
    sub applies_to {'PPI::Token::Word'}
    sub fix_safety {'unsafe'}

    sub check ( $self, $elem, $doc ) {
        return $self->violation( $elem, message => '...' );
    }
    sub fix ( $self, $violation, $fix ) { ...; return 1 }

=head1 DESCRIPTION

Subclasses override the class methods C<code>, C<summary>, C<explanation>,
C<applies_to> (a class name or list of them; default C<PPI::Element>),
C<fix_safety> (C<safe>, C<unsafe> or C<none>; default C<none>) and C<options> (hashref of
name to default). C<check> returns zero or more violations; C<fix> records
edits on a L<Puff::Fix> and returns true, or returns false (or dies) to
decline.

C<< $self->option($name) >> returns the configured value, else the default.
C<< $self->violation($elem, message => ..., fixable => 0|1) >> fills in the
rule, code, line and column; C<fixable> defaults to 1 and is always 0 when
C<fix_safety> is C<none>.

=cut
