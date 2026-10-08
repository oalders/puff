package Puff::Rule::Security::InsecureRand;

use v5.36;
use parent 'Puff::Rule';

use Puff::PPIUtil qw( is_builtin_call );

my $IMPORT = 'use Math::Random::Secure qw(rand);';
my %WATCHED = map { $_ => 1 } qw( rand srand CORE::rand CORE::srand );

sub code       {'S001'}
sub summary    {'rand/srand is not cryptographically secure'}
sub applies_to {'PPI::Token::Word'}
sub fix_safety {'unsafe'}

sub explanation {
    return <<~'END';
        Perl's built-in rand is a fast pseudo-random number generator seeded
        from a small amount of state. Its output can be predicted, so it must
        not be used for passwords, tokens, session ids, salts or anything else
        an attacker should not be able to guess. srand only makes this worse by
        fixing the seed.

        The fix adds `use Math::Random::Secure qw(rand);` so that plain rand
        calls use a cryptographically secure generator. The line is added once
        per file, after the last use/no statement before the first rand call
        (or before that call's statement), and only when the file has no
        package statement or a single `package NAME;` before that call;
        otherwise rand is reported as not fixable.

        srand, CORE::rand and CORE::srand are reported but not fixed: an import
        cannot override CORE::rand, and seeding a secure generator has no
        meaningful equivalent.

        The fix is unsafe because it changes which random number generator the
        code uses and adds a dependency on Math::Random::Secure.
        END
}

sub check ( $self, $elem, $doc ) {
    my $name = $elem->content;
    return unless $WATCHED{$name} && is_builtin_call($elem);

    if ( $name eq 'rand' ) {
        return if _has_secure_import($doc);
        return $self->violation(
            $elem,
            message => 'rand is not cryptographically secure; use Math::Random::Secure',
            fixable => _import_position($doc) ? 1 : 0,
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
    my ( $where, $stmt ) = _import_position( $elem->top ) or return 0;

    if ( $where eq 'after' ) {
        $fix->insert_after( $stmt, "\n$IMPORT" );
    }
    else {
        $fix->insert_before( $stmt, "$IMPORT\n" );
    }
    return 1;
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

    my ($anchor) = reverse grep {
               $_->isa('PPI::Statement::Include')
            && ( $_->type eq 'use' || $_->type eq 'no' )
    } @top[ $start_idx .. $target_idx - 1 ];
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
        next unless $inc->type eq 'use' && ( $inc->module // '' ) eq 'Math::Random::Secure';
        for my $words ( @{ $inc->find('PPI::Token::QuoteLike::Words') || [] } ) {
            return 1 if grep { $_ eq 'rand' } $words->literal;
        }
        for my $quote ( @{ $inc->find('PPI::Token::Quote') || [] } ) {
            return 1 if $quote->string eq 'rand';
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
Plain C<rand> is not reported when the file already has
C<use Math::Random::Secure> importing C<rand>.

The unsafe fix inserts C<use Math::Random::Secure qw(rand);> once per file,
where it is compiled before the first C<rand> call. It declines when the file
has more than one C<package> statement, a block-form C<package>, or a
C<package> statement after the first call; in those files plain C<rand> is
reported with C<fixable> 0. The other forms are always reported with
C<fixable> 0.

=cut
