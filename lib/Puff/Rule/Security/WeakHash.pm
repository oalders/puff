package Puff::Rule::Security::WeakHash;

use v5.36;
use parent 'Puff::Rule';

use Puff::PPIUtil qw( is_builtin_call call_args );

my %WEAK_MODULE = map { $_ => 1 } qw( Digest::MD2 Digest::MD4 Digest::MD5 Digest::Perl::MD5 Digest::SHA1 );
my %SHA_MODULE  = map { $_ => 1 } qw( Digest::SHA Digest::SHA::PurePerl );
my $WEAK_NAME   = qr/\A(?:MD[245]|SHA-?1)\z/i;

sub code       {'S006'}
sub summary    {'Do not use MD5, SHA-1 or crypt for security'}
sub applies_to {'PPI::Token::Word'}
sub cwe        { ( 327, 328, 916 ) }

sub explanation {
    return <<~'END';
        MD5 and SHA-1 have practical collision attacks, and MD2 and MD4 are
        worse (CWE-327, CWE-328). crypt() usually means DES or MD5-crypt,
        which are far too fast and weak for passwords (CWE-916).

        The rule reports:

        - `use` or `require` of Digest::MD5, Digest::MD4, Digest::MD2,
          Digest::SHA1 or Digest::Perl::MD5;
        - importing a sha1* function from Digest::SHA (or
          Digest::SHA::PurePerl), or calling one by its full name;
        - `Digest->new('MD5')`, `Digest->new('SHA-1')` and similar;
        - `Digest::SHA->new` with no algorithm (it defaults to SHA-1) or with
          algorithm 1;
        - calls to crypt.

        Use SHA-256 or better (Digest::SHA's sha256_hex) for integrity, and a
        password hash such as Crypt::Argon2 or Crypt::Bcrypt for passwords.
        When a protocol or file format requires MD5 or SHA-1, or the hash is a
        checksum or cache key with no security role, suppress the violation:
        `# puff: ignore[S006]`. There is no fix.

        Ruff's equivalent is S324.
        END
}

sub check ( $self, $elem, $doc ) {
    my $name   = $elem->content;
    my $parent = $elem->parent;

    if ( $parent && $parent->isa('PPI::Statement::Include') ) {
        return unless ( $parent->module // '' ) eq $name;
        return $self->_report( $elem, "$name is a weak hash (CWE-328)" ) if $WEAK_MODULE{$name};
        return $self->_report( $elem, "SHA-1 imported from $name is a weak hash (CWE-328)" )
            if $SHA_MODULE{$name} && _imports_sha1($parent);
        return;
    }

    if ( $name =~ /\A(.+)::sha1\w*\z/ && $SHA_MODULE{$1} ) {
        return $self->_report( $elem, "$name is a weak hash (CWE-328)" );
    }

    if ( ( $name eq 'Digest' || $SHA_MODULE{$name} ) && _is_new_call($elem) ) {
        my $args = call_args( $elem->snext_sibling->snext_sibling );
        my $alg  = @$args && @{ $args->[0] } == 1 ? $args->[0][0] : undef;
        if ( $name eq 'Digest' ) {
            return unless $alg && $alg->isa('PPI::Token::Quote') && $alg->string =~ $WEAK_NAME;
            return $self->_report( $elem, 'Digest->new(' . $alg->content . ') is a weak hash (CWE-328)' );
        }
        return $self->_report( $elem, "$name->new without an algorithm is SHA-1, a weak hash (CWE-328)" ) unless @$args;
        return unless $alg && _alg_is_sha1($alg);
        return $self->_report( $elem, "$name->new(" . $alg->content . ') is SHA-1, a weak hash (CWE-328)' );
    }

    if ( $name eq 'crypt' && is_builtin_call($elem) ) {
        return $self->_report( $elem, 'crypt is a weak password hash (CWE-916)' );
    }
    return;
}

sub _report ( $self, $elem, $message ) {
    return $self->violation( $elem, message => $message );
}

sub _imports_sha1 ($include) {
    for my $words ( @{ $include->find('PPI::Token::QuoteLike::Words') || [] } ) {
        return 1 if grep {/\Asha1/} $words->literal;
    }
    for my $quote ( @{ $include->find('PPI::Token::Quote') || [] } ) {
        return 1 if $quote->string =~ /\Asha1/;
    }
    return 0;
}

# CLASS->new
sub _is_new_call ($elem) {
    my $arrow = $elem->snext_sibling;
    return 0 unless $arrow && $arrow->isa('PPI::Token::Operator') && $arrow->content eq '->';
    my $method = $arrow->snext_sibling;
    return $method && $method->isa('PPI::Token::Word') && $method->content eq 'new';
}

sub _alg_is_sha1 ($alg) {
    return $alg->literal == 1 if $alg->isa('PPI::Token::Number') && $alg->can('literal') && defined $alg->literal;
    return $alg->string =~ /\A(?:1|sha-?1)\z/i if $alg->isa('PPI::Token::Quote');
    return 0;
}

1;

# ABSTRACT: S006 - do not use MD5, SHA-1 or crypt for security

__END__

=pod

=head1 DESCRIPTION

Reports MD2, MD4, MD5 and SHA-1 digest modules and constructors, SHA-1
functions from Digest::SHA, and C<crypt>. There is no fix.

=cut
