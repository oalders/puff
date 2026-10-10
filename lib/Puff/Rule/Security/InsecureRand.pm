package Puff::Rule::Security::InsecureRand;

use v5.36;
use parent 'Puff::Rule';

use Puff::PPIUtil qw( is_builtin_call );
use Scalar::Util  qw( weaken );

my $IMPORT = 'use Crypt::PRNG qw(rand);';

# Modules whose rand is a secure drop-in, and the import tags that include it.
my %SECURE_RAND = (
    'Crypt::PRNG'          => { rand => 1, ':all' => 1 },
    'Math::Random::Secure' => { rand => 1 },
);
my %WATCHED = map { $_ => 1 } qw( rand srand CORE::rand CORE::srand );

sub code       {'S001'}
sub summary    {'rand/srand is not cryptographically secure'}
sub applies_to {'PPI::Token::Word'}
sub fix_safety {'unsafe'}
sub cwe        {338}

sub explanation {
    return <<~'END';
        Perl's built-in rand is a fast pseudo-random number generator seeded
        from a small amount of state. Its output can be predicted, so it must
        not be used for passwords, tokens, session ids, salts or anything else
        an attacker should not be able to guess. srand only makes this worse by
        fixing the seed.

        The fix adds `use Crypt::PRNG qw(rand);` so that plain rand calls use
        a cryptographically secure generator. Crypt::PRNG's rand takes the same
        argument and returns the same range as the built-in. The line is added
        once per file, after the last use/no statement before the first rand
        call (or before that call's statement), and only when the file has no
        package statement or a single `package NAME;` before that call;
        otherwise rand is reported as not fixable.

        Plain rand is not reported when the file already imports rand from
        Crypt::PRNG (by name or with `:all`) or from Math::Random::Secure.

        When the random value becomes a key, token, salt or session id, prefer
        random bytes over a float: `random_bytes` from Crypt::PRNG or
        Crypt::SysRandom. Rewriting such code is left to you.

        srand, CORE::rand and CORE::srand are reported but not fixed: an import
        cannot override CORE::rand, and seeding a secure generator has no
        meaningful equivalent.

        The fix is unsafe because it changes which random number generator the
        code uses and adds a dependency on Crypt::PRNG (from CryptX).
        END
}

sub check ( $self, $elem, $doc ) {
    my $name = $elem->content;
    return unless $WATCHED{$name} && is_builtin_call($elem);

    if ( $name eq 'rand' ) {
        my $facts = $self->_doc_facts($doc);
        return if $facts->{secure_import};
        return $self->violation(
            $elem,
            message => 'rand is not cryptographically secure; use Crypt::PRNG, or random_bytes for keys and tokens',
            fixable => @{ $facts->{import_position} } ? 1 : 0,
        );
    }
    return $self->violation(
        $elem,
        message => "$name is not cryptographically secure",
        fixable => 0,
    );
}

sub fix ( $self, $violation, $fix ) {
    my $elem = $violation->element;
    return 0 unless $elem->content eq 'rand';
    my ( $where, $stmt ) = @{ $self->_doc_facts( $elem->top )->{import_position} } or return 0;

    if ( $where eq 'after' ) {
        $fix->insert_after( $stmt, "\n$IMPORT" );
    }
    else {
        $fix->insert_before( $stmt, "$IMPORT\n" );
    }
    return 1;
}

# Both answers depend only on the whole document, so they are computed once
# per document rather than once per rand call. The weakened reference goes
# undef when the document is freed, so a re-parsed document (a new fix pass
# or the next file) never sees another document's answers. This relies on
# fixes being text edits: a document is never changed in place.
sub _doc_facts ( $self, $doc ) {
    unless ( $self->{facts_doc} && $self->{facts_doc} == $doc ) {
        $self->{facts_doc} = $doc;
        weaken( $self->{facts_doc} );
        $self->{facts} = {
            secure_import   => _has_secure_import($doc),
            import_position => [ _import_position($doc) ],
        };
    }
    return $self->{facts};
}

# Where the import goes so that it is compiled before the first plain rand
# call: ('after', $statement) or ('before', $statement), or an empty list
# when the file's package layout means there is no safe place.
sub _import_position ($doc) {
    my ($first) = grep { $_->content eq 'rand' && is_builtin_call($_) } @{ $doc->find('PPI::Token::Word') || [] };
    my $target = _top_level_statement($first) or return;

    my @top = $doc->schildren;
    my ($target_idx) = grep { $top[$_] == $target } 0 .. $#top;

    my $packages = $doc->find('PPI::Statement::Package') || [];
    return if @$packages > 1;
    my $start_idx = 0;
    if ( my ($pkg) = @$packages ) {
        return if $pkg->find_first('PPI::Structure::Block');
        my ($pkg_idx) = grep { $top[$_] == $pkg } 0 .. $#top;
        return unless defined $pkg_idx && $pkg_idx < $target_idx;
        $start_idx = $pkg_idx;
    }

    my ($anchor)
        = reverse grep { $_->isa('PPI::Statement::Include') && ( $_->type eq 'use' || $_->type eq 'no' ) }
        @top[ $start_idx .. $target_idx - 1 ];
    $anchor //= $packages->[0];

    return $anchor ? ( after => $anchor ) : ( before => $target );
}

sub _top_level_statement ($elem) {
    my $node = $elem or return;
    while ( my $parent = $node->parent ) {
        return $node if $parent->isa('PPI::Document');
        $node = $parent;
    }
    return;
}

sub _has_secure_import ($doc) {
    my $includes = $doc->find('PPI::Statement::Include') || [];
    for my $inc (@$includes) {
        next unless $inc->type eq 'use';
        my $wanted = $SECURE_RAND{ $inc->module // '' } or next;
        for my $words ( @{ $inc->find('PPI::Token::QuoteLike::Words') || [] } ) {
            return 1 if grep { $wanted->{$_} } $words->literal;
        }
        for my $quote ( @{ $inc->find('PPI::Token::Quote') || [] } ) {
            return 1 if $wanted->{ $quote->string };
        }
    }
    return 0;
}

1;

# ABSTRACT: S001 - rand/srand is not cryptographically secure

__END__

=pod

=head1 DESCRIPTION

Reports calls to C<rand>, C<srand>, C<CORE::rand> and C<CORE::srand>
(not methods, hash keys, sub names or C<package>/C<use>/C<no> statements).
Plain C<rand> is not reported when the file already imports C<rand> from
L<Crypt::PRNG> (by name or with C<:all>) or from L<Math::Random::Secure>.

The unsafe fix inserts C<use Crypt::PRNG qw(rand);> once per file,
where it is compiled before the first C<rand> call. It declines when the file
has more than one C<package> statement, a block-form C<package>, or a
C<package> statement after the first call; in those files plain C<rand> is
reported with C<fixable> 0. The other forms are always reported with
C<fixable> 0.

=cut
