package Puff::Rule::Security::TLSVerifyDisabled;

use v5.36;
use parent 'Puff::Rule';

# Option names that turn verification off when given a false value.
my %OFF_WHEN_FALSE = map { $_ => 1 } qw( verify_hostname verify_SSL SSL_verify_mode );

my $ENV_KEY = 'PERL_LWP_SSL_VERIFY_HOSTNAME';

sub code       {'S005'}
sub summary    {'Do not turn off TLS certificate verification'}
sub applies_to { [ 'PPI::Token::Word', 'PPI::Token::Quote' ] }
sub cwe        {295}

sub explanation {
    return <<~'END';
        Without certificate verification, anyone who can intercept the
        connection can pretend to be the server and read or change the
        traffic (CWE-295, improper certificate validation).

        The rule reports a literal that turns verification off:

        - `verify_hostname => 0` (LWP::UserAgent ssl_opts),
          `verify_SSL => 0` (HTTP::Tiny), `SSL_verify_mode => 0` or
          `SSL_verify_mode => SSL_VERIFY_NONE` (IO::Socket::SSL), where the
          value is 0, '0', '' or SSL_VERIFY_NONE;
        - `insecure => 1` and `->insecure(1)` (Mojo::UserAgent), with any
          non-zero number;
        - `$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0` (or '0' or '').

        Values computed at runtime are not reported. There is no fix: turning
        verification on can break a connection that relies on it being off,
        so fix the certificate (or point SSL_ca_file at the right CA) instead.

        Ruff's equivalent is S501.
        END
}

sub check ( $self, $elem, $doc ) {
    my $name = _name($elem) // return;

    if ( $OFF_WHEN_FALSE{$name} || $name eq 'insecure' ) {
        my $op = $elem->snext_sibling;
        if ( _is_op( $op, '=>' ) ) {
            my $value = $op->snext_sibling;
            return $self->_report($elem) if $name eq 'insecure' ? _is_true($value) : _is_false( $value, $name );
        }
        elsif ( $name eq 'insecure' && _is_op( $elem->sprevious_sibling, '->' ) ) {
            my $list = $elem->snext_sibling;
            my @args = $list && $list->isa('PPI::Structure::List') ? map { $_->schildren } $list->schildren : ();
            return $self->_report($elem) if @args == 1 && _is_true( $args[0] );
        }
        return;
    }

    if ( $name eq $ENV_KEY ) {
        my $expr      = $elem->parent                     or return;
        my $subscript = $expr->parent                      or return;
        return unless $expr->schildren == 1 && $subscript->isa('PPI::Structure::Subscript');
        my $hash = $subscript->sprevious_sibling;
        return unless $hash && $hash->isa('PPI::Token::Symbol') && $hash->content eq '$ENV';
        my $op = $subscript->snext_sibling;
        return $self->_report($elem) if _is_op( $op, '=' ) && _is_false( $op->snext_sibling, '' );
    }
    return;
}

sub _report ( $self, $elem ) {
    return $self->violation( $elem, message => 'TLS certificate verification is turned off (CWE-295)' );
}

sub _name ($elem) {
    return $elem->content if $elem->isa('PPI::Token::Word');
    return $elem->string  if $elem->isa('PPI::Token::Quote');
    return;
}

sub _is_op ( $elem, $op ) {
    return $elem && $elem->isa('PPI::Token::Operator') && $elem->content eq $op;
}

sub _is_false ( $elem, $name ) {
    return 0 unless $elem;
    return $elem->literal == 0 if $elem->isa('PPI::Token::Number') && $elem->can('literal') && defined $elem->literal;
    return $elem->string eq '' || $elem->string eq '0' if $elem->isa('PPI::Token::Quote');
    return $elem->content =~ /(?:\A|::)SSL_VERIFY_NONE\z/ if $name eq 'SSL_verify_mode' && $elem->isa('PPI::Token::Word');
    return 0;
}

sub _is_true ($elem) {
    return $elem && $elem->isa('PPI::Token::Number') && $elem->can('literal') && defined $elem->literal && $elem->literal != 0;
}

1;

# ABSTRACT: S005 - do not turn off TLS certificate verification

__END__

=pod

=head1 DESCRIPTION

Reports literal options that turn TLS certificate verification off in
LWP::UserAgent, HTTP::Tiny, IO::Socket::SSL and Mojo::UserAgent, and
C<$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME}> set to a false literal. There is no
fix.

=cut
