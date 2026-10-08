package Puff::Rule::Security::PredictableToken;

use v5.36;
use parent 'Puff::Rule';

use Puff::PPIUtil qw( is_builtin_call call_args );

my $HASH_FUNCTION = qr/(?:\A|::)(?:md5|sha(?:1|224|256|384|512|512224|512256))(?:_hex|_base64)?\z/;
my %GUESSABLE     = map { $_ => 1 } qw( time localtime gmtime times rand srand gettimeofday );
my $PID_IN_STRING = qr/(?<!\\)(?:\\\\)*\$\$(?![\w{])/;

sub code       {'S010'}
sub summary    {'Do not hash the time, PID or rand to make a token'}
sub applies_to {'PPI::Token::Word'}
sub cwe        { ( 340, 338 ) }

sub explanation {
    return <<~'END';
        Hashing the time, the process ID or rand does not make a value
        unpredictable: the hash only hides inputs that an attacker can guess
        or enumerate. A session ID, password-reset token, CSRF token, nonce
        or salt built this way can be brute forced (CWE-340, CWE-338).
        Several CPAN session modules have had CVEs for exactly this, such as
        `md5_hex( time . $$ . rand )`.

        The rule reports md5 and sha* functions (from Digest::MD5 or
        Digest::SHA, with any `_hex` or `_base64` suffix) whose arguments use
        `time`, `localtime`, `gmtime`, `times`, `gettimeofday`, `rand`,
        `srand` or `$$`.

        Take the bytes from a CSPRNG instead:

            use Crypt::PRNG qw( random_bytes_hex );
            my $token = random_bytes_hex(32);

        or Crypt::SysRandom's `random_bytes`. When the hash is a cache key or
        a unique file name with no security role, suppress the violation:
        `# puff: ignore[S010]`. There is no fix.
        END
}

sub check ( $self, $elem, $doc ) {
    my $name = $elem->content;
    return unless $name =~ $HASH_FUNCTION && is_builtin_call($elem);
    my $prev = $elem->sprevious_sibling;
    return if $prev && $prev->isa('PPI::Token::Operator') && $prev->content eq '->';

    my %found;
    for my $el ( map {@$_} @{ call_args($elem) } ) {
        for my $token ( $el->isa('PPI::Node') ? $el->tokens : $el ) {
            if ( $token->isa('PPI::Token::Magic') && $token->content eq '$$' ) {
                $found{'$$'} = 1;
            }
            elsif ( $token->isa('PPI::Token::Word') ) {
                my $word = $token->content =~ s/\A(?:CORE|Time::HiRes)::(?=\w+\z)//r;
                $found{$word} = 1 if $GUESSABLE{$word} && is_builtin_call($token);
            }
            elsif (( $token->isa('PPI::Token::Quote::Double') || $token->isa('PPI::Token::Quote::Interpolate') )
                && $token->string =~ $PID_IN_STRING ) {
                $found{'$$'} = 1;
            }
        }
    }
    return unless %found;
    my $sources = join '/', sort keys %found;
    return $self->violation( $elem,
        message => "$name of $sources is predictable (CWE-340); use random_bytes from Crypt::PRNG or Crypt::SysRandom" );
}

1;

# ABSTRACT: S010 - do not hash the time, PID or rand to make a token

__END__

=pod

=head1 DESCRIPTION

Reports md5 and sha* digest functions whose arguments include the time, the
process ID or C<rand>. There is no fix.

=cut
