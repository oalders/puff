package Puff::Rule::Security::TLSVerifyDisabled;

use v5.36;
use parent 'Puff::Rule';

# Option names that turn verification off when given a false value.
my %OFF_WHEN_FALSE = map { $_ => 1 } qw( verify_hostname verify_SSL SSL_verify_mode );

# Option names that turn SSH host key checking off with a false value or 'no'.
my %SSH_STRICT = map { $_ => 1 } qw( strict_hostkeycheck strict_host_key_checking );

my $ENV_KEY = 'PERL_LWP_SSL_VERIFY_HOSTNAME';

sub code       {'S005'}
sub summary    {'Do not turn off TLS certificate or SSH host key verification'}
sub applies_to { [ 'PPI::Token::Word', 'PPI::Token::Quote' ] }
sub fix_safety {'unsafe'}
sub cwe        {295}

sub explanation {
    return <<~'END';
        Without certificate verification, anyone who can intercept the
        connection can pretend to be the server and read or change the
        traffic (CWE-295, improper certificate validation). The same goes for
        an SSH client that does not check the server's host key.

        The rule reports a literal that turns verification off:

        - `verify_hostname => 0` (LWP::UserAgent ssl_opts),
          `verify_SSL => 0` (HTTP::Tiny), `SSL_verify_mode => 0` or
          `SSL_verify_mode => SSL_VERIFY_NONE` (IO::Socket::SSL), where the
          value is 0, '0', '' or SSL_VERIFY_NONE;
        - `insecure => 1` and `->insecure(1)` (Mojo::UserAgent), with any
          non-zero number;
        - `$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0` (or '0' or '');
        - `strict_hostkeycheck => 0` and `strict_host_key_checking => 'no'`
          (Net::SSH::Perl and friends), with 0, '0', '', 'no' or 'off';
        - a string holding the ssh option `StrictHostKeyChecking=no` (or
          `StrictHostKeyChecking no`), as passed to Net::OpenSSH or ssh.

        Values computed at runtime are not reported.

        The unsafe fix turns TLS verification back on: the false value becomes
        1, SSL_VERIFY_NONE becomes SSL_VERIFY_PEER, and `insecure` gets 0. It
        is unsafe because a connection that only worked with verification off
        will now fail; fix the certificate (or point SSL_ca_file at the right
        CA) as well. SSH settings are not fixed, since whether `yes` or
        `accept-new` is right depends on how host keys are managed.

        Ruff's equivalents are S501 and S507.
        END
}

sub check ( $self, $elem, $doc ) {
    my ($kind) = _finding($elem) or return;
    return $self->violation(
        $elem,
        message => $kind eq 'ssh'
        ? 'SSH host key checking is turned off (CWE-295)'
        : 'TLS certificate verification is turned off (CWE-295)',
        fixable => $kind eq 'ssh' ? 0 : 1,
    );
}

sub fix ( $self, $violation, $fix ) {
    my ( $kind, $value ) = _finding( $violation->element ) or return 0;
    return 0 if $kind eq 'ssh';
    my $text
        = $kind eq 'insecure'                                        ? '0'
        : $value->isa('PPI::Token::Word')                            ? $value->content =~ s/SSL_VERIFY_NONE\z/SSL_VERIFY_PEER/r
        :                                                              '1';
    $fix->replace( $value, $text );
    return 1;
}

# ( kind, value element ) when $elem turns verification off: kind is 'tls',
# 'insecure' or 'ssh'. The value is the element a fix would replace.
sub _finding ($elem) {
    if ( $elem->isa('PPI::Token::Quote') && $elem->string =~ /\bStrictHostKeyChecking\s*[= ]\s*no\b/i ) {
        return ( ssh => $elem );
    }
    my $name = _name($elem) // return;

    if ( $SSH_STRICT{$name} ) {
        my $op = $elem->snext_sibling;
        return unless _is_op( $op, '=>' );
        my $value = $op->snext_sibling;
        return ( ssh => $value ) if _is_false( $value, $name ) || _is_no($value);
        return;
    }

    if ( $OFF_WHEN_FALSE{$name} || $name eq 'insecure' ) {
        my $op = $elem->snext_sibling;
        if ( _is_op( $op, '=>' ) ) {
            my $value = $op->snext_sibling;
            return ( insecure => $value ) if $name eq 'insecure' && _is_true($value);
            return ( tls => $value )      if $name ne 'insecure' && _is_false( $value, $name );
        }
        elsif ( $name eq 'insecure' && _is_op( $elem->sprevious_sibling, '->' ) ) {
            my $list = $elem->snext_sibling;
            my @args = $list && $list->isa('PPI::Structure::List') ? map { $_->schildren } $list->schildren : ();
            return ( insecure => $args[0] ) if @args == 1 && _is_true( $args[0] );
        }
        return;
    }

    if ( $name eq $ENV_KEY ) {
        my $expr      = $elem->parent or return;
        my $subscript = $expr->parent or return;
        return unless $expr->schildren == 1 && $subscript->isa('PPI::Structure::Subscript');
        my $hash = $subscript->sprevious_sibling;
        return unless $hash && $hash->isa('PPI::Token::Symbol') && $hash->content eq '$ENV';
        my $op = $subscript->snext_sibling;
        return unless _is_op( $op, '=' );
        my $value = $op->snext_sibling;
        return ( tls => $value ) if _is_false( $value, '' );
    }
    return;
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

sub _is_no ($elem) {
    return $elem && $elem->isa('PPI::Token::Quote') && $elem->string =~ /\A(?:no|off)\z/i;
}

sub _is_true ($elem) {
    return $elem && $elem->isa('PPI::Token::Number') && $elem->can('literal') && defined $elem->literal && $elem->literal != 0;
}

1;

# ABSTRACT: S005 - do not turn off TLS certificate or SSH host key verification

__END__

=pod

=head1 DESCRIPTION

Reports literal options that turn TLS certificate verification off in
LWP::UserAgent, HTTP::Tiny, IO::Socket::SSL and Mojo::UserAgent,
C<$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME}> set to a false literal, and SSH host
key checking turned off. The unsafe fix turns TLS verification back on.

=cut
