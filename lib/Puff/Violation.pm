package Puff::Violation;

use v5.36;

sub new ( $class, %args ) {
    return bless {%args}, $class;
}

sub rule    ($self) { $self->{rule} }
sub code    ($self) { $self->{code} }
sub element ($self) { $self->{element} }
sub line    ($self) { $self->{line} }
sub column  ($self) { $self->{column} }
sub message ($self) { $self->{message} }

# The violation's own fix safety when the rule gave one, else the rule's.
# A rule that declares none (or no rule at all) wins over the violation, so
# the engine and every reporter agree that it is never fixed.
sub fix_safety ($self) {
    my $rule = $self->{rule} or return 'none';
    return 'none' if $rule->fix_safety eq 'none';
    return $self->{fix_safety} // $rule->fix_safety;
}

sub fixable ( $self, @set ) {
    $self->{fixable} = $set[0] if @set;
    return 0 if $self->fix_safety eq 'none';
    return $self->{fixable};
}

sub file ( $self, @set ) {
    $self->{file} = $set[0] if @set;
    return $self->{file};
}

1;

# ABSTRACT: One problem a rule found in a file

__END__

=pod

=head1 DESCRIPTION

Holds the rule, code, element, 1-based line and column (in characters),
message, whether a fix is offered, how safe that fix is, and the file.
C<fix_safety> is the safety given to L<Puff::Rule/violation>, else the
rule's C<fix_safety>. It is C<none> when there is no rule or the rule's
C<fix_safety> is C<none>, whatever the violation was given, and then
C<fixable> is always 0. C<file> and C<fixable> are
getters and, given an argument, setters, because the engine fills in the
file after C<check> and withdraws the fix offer for files it will not fix.

=cut
