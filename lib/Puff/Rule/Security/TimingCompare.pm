package Puff::Rule::Security::TimingCompare;

use v5.36;
use parent 'Puff::Rule';

use Scalar::Util qw( weaken );

use Puff::PPIUtil qw( is_constant_string );

my $SUFFIX        = qr/s?(?:_(?:hex|b64|base64|bytes))?\z/i;
my $STRONG_NAME   = qr/(?:\A|_)(?:password|passwd|secret|csrf|nonce|hmac)$SUFFIX|\Ahmac_/i;
my $WEAK_NAME     = qr/(?:\A|_)(?:token|sig|signature|digest|mac|hash)$SUFFIX/i;
my $CRYPTO_MODULE = qr/(?:\A|::)(?:Crypt|Authen|Authentication|OAuth\w*|JWT|WebToken|Session|HMAC\w*)(?:::|\z)/;

sub code       {'S011'}
sub summary    {'Compare secrets in constant time'}
sub applies_to {'PPI::Token::Operator'}
sub cwe        {208}

sub explanation {
    return <<~'END';
        `eq` and `ne` stop at the first byte that differs, so how long a
        comparison takes says how much of the guess was right. An attacker
        who can time many requests can recover an HMAC, signature or token a
        byte at a time (CWE-208).

        The rule reports `eq` and `ne` where one side looks like a secret and
        the other side is not a constant. A side looks like a secret when it
        is a variable, hash key, method or function whose name ends in:

        - password, passwd, secret, csrf, nonce or hmac, or that starts with
          hmac_ (`$self->{csrf_token}`, `hmac_sha256_hex(...)`);
        - token, sig, signature, digest, mac or hash, but only in a file
          that calls or imports an hmac function, or that uses or declares a
          package with Crypt, Authen, Authentication, OAuth, JWT, WebToken,
          Session or HMAC as part of its name (Crypt::PBKDF2, Mojo::JWT,
          Net::OAuth::SignatureMethod::PLAINTEXT). On their own these names
          are too common: parsers have tokens, sig is often a sigil or a type
          signature, and hash is usually a data structure.

        Any of these may be followed by _hex, _b64, _base64 or _bytes. This is
        a name heuristic: it misses secrets with other names, and can still
        report values that are not secret.

        Compare in constant time instead, for example with
        String::Compare::ConstantTime:

            use String::Compare::ConstantTime qw( equals );
            die 'bad signature' unless equals( $sig, $expected );

        or compare hashes of both sides. For passwords, verify with the
        password hashing module (Crypt::Argon2's argon2_verify, Crypt::Bcrypt's
        bcrypt_check), which also compares in constant time. Suppress the
        violation where the value is not secret: `# puff: ignore S011`.
        There is no fix.
        END
}

sub check ( $self, $elem, $doc ) {
    my $op = $elem->content;
    return unless $op eq 'eq' || $op eq 'ne';
    my $left  = $elem->sprevious_sibling or return;
    my $right = $elem->snext_sibling     or return;
    return if _is_constant($left) || _is_constant($right);

    my ($name) = grep { defined && $self->_is_secret_name( $_, $doc ) } _left_name($left), _right_name($right);
    return unless defined $name;
    return $self->violation(
        $elem,
        message => "'$op' on $name leaks timing (CWE-208); use a constant-time comparison"
    );
}

sub _is_secret_name ( $self, $name, $doc ) {
    return 1 if $name     =~ $STRONG_NAME;
    return 0 unless $name =~ $WEAK_NAME;
    unless ( $self->{crypto_doc} && $self->{crypto_doc} == $doc ) {
        $self->{crypto_doc} = $doc;
        weaken( $self->{crypto_doc} );
        $self->{uses_crypto} = _uses_crypto($doc);
    }
    return $self->{uses_crypto};
}

sub _uses_crypto ($doc) {
    return $doc->find_first(
        sub {
            my $el = $_[1];
            return 1 if $el->isa('PPI::Statement::Include') && ( $el->module // '' ) =~ $CRYPTO_MODULE;
            return 1 if $el->isa('PPI::Statement::Package') && $el->namespace        =~ $CRYPTO_MODULE;
            return 1 if $el->isa('PPI::Token::Word')        && $el->content          =~ /(?:\A|::)hmac_/i;
            return 1 if $el->isa('PPI::Token::QuoteLike::Words') && grep {/\Ahmac_/i} $el->literal;
            return 0;
        }
    ) ? 1 : 0;
}

# A literal, undef or a bareword constant such as COMMA.
sub _is_constant ($el) {
    return 1 if $el->isa('PPI::Token::Number');
    if ( $el->isa('PPI::Token::Word') ) {
        my $next = $el->snext_sibling;
        return 1 if $el->content =~ /\A[A-Z][A-Z0-9_]*\z/ && !( $next && $next->isa('PPI::Structure::List') );
    }
    return 1 if $el->isa('PPI::Token::Word') && $el->content eq 'undef';
    return is_constant_string($el);
}

# The name of the operand that ends at $el: `$sig`, `$x->{sig}`, `$x->sig`,
# `$x->sig()`, `sig(...)`.
sub _left_name ($el) {
    if ( $el->isa('PPI::Structure::List') ) {
        my $prev = $el->sprevious_sibling;
        return $prev && $prev->isa('PPI::Token::Word') ? _word_name($prev) : undef;
    }
    return _key_name($el) if $el->isa('PPI::Structure::Subscript');
    return _word_name($el) if $el->isa('PPI::Token::Word');
    return _symbol_name($el) if $el->isa('PPI::Token::Symbol');
    return undef;
}

# The name of the operand that starts at $el; follows `->` chains and
# subscripts to the last name.
sub _right_name ($el) {
    my $name = _left_name($el);
    for ( my $next = $el->snext_sibling ; $next ; $next = $next->snext_sibling ) {
        if ( $next->isa('PPI::Token::Operator') ) {
            last unless $next->content eq '->';
            next;
        }
        if    ( $next->isa('PPI::Structure::Subscript') ) { $name = _key_name($next) }
        elsif ( $next->isa('PPI::Token::Word') )          { $name = _word_name($next) }
        elsif ( !$next->isa('PPI::Structure::List') )     {last}
    }
    return $name;
}

sub _symbol_name ($symbol) {
    return $symbol->content =~ /(\w+)\z/ ? $1 : undef;
}

sub _word_name ($word) {
    return $word->content =~ /(\w+)\z/ ? $1 : undef;
}

sub _key_name ($subscript) {
    my @kids = $subscript->schildren;
    return undef unless @kids == 1;
    my @parts = $kids[0]->schildren;
    return undef unless @parts == 1;
    my $key = $parts[0];
    return $key->content if $key->isa('PPI::Token::Word');
    return $key->string if is_constant_string($key);
    return undef;
}

1;

# ABSTRACT: S011 - compare secrets in constant time

__END__

=pod

=head1 DESCRIPTION

Reports C<eq> and C<ne> where one side is named like a signature, token or
other secret and the other side is not a constant. There is no fix.

=cut
