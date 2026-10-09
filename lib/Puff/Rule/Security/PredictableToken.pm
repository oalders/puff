package Puff::Rule::Security::PredictableToken;

use v5.36;
use parent 'Puff::Rule';

use Puff::PPIUtil qw( is_builtin_call call_args );

my $HASH_FUNCTION
    = qr/(?:\A|::)(?:md[245]|sha(?:1|224|256|384|512|512224|512256)|digest_data)(?:_hex|_base64|_b64u?)?\z/;
my %GUESSABLE     = map { $_ => 1 } qw( time localtime gmtime times rand srand gettimeofday clock_gettime refaddr );
my $PID_IN_STRING = qr/(?<!\\)(?:\\\\)*\$(?:\$(?![\w{])|\{?(?:PID|PROCESS_ID)\b)/;
my %PID_VARIABLE  = map { $_ => 1 } qw( $PID $PROCESS_ID $English::PID $English::PROCESS_ID );

sub code       {'S010'}
sub summary    {'Do not hash the time, PID or rand to make a token'}
sub applies_to {'PPI::Token::Word'}
sub cwe        { ( 340, 338 ) }

sub explanation {
    return <<~'END';
        Hashing the time, the process ID or rand does not make a value
        unpredictable: the hash only hides inputs that an attacker can guess
        or enumerate. A session ID, password-reset token, CSRF token, nonce
        or salt built this way, such as `md5_hex( time . $$ . rand )`, can be
        brute forced (CWE-340, CWE-338).

        The rule reports md2, md4, md5 and sha* functions (from Digest::MD5,
        Digest::SHA, Crypt::Digest and the like, with any `_hex`, `_base64`,
        `_b64` or `_b64u` suffix) and Crypt::Digest's `digest_data*` whose
        arguments use `time`, `localtime`, `gmtime`, `times`,
        `gettimeofday`, `clock_gettime`, `rand`, `srand`, `refaddr`, `$$`
        or English's `$PID` and `$PROCESS_ID`.

        Take the bytes from a CSPRNG instead:

            use Crypt::PRNG qw( random_bytes_hex );
            my $token = random_bytes_hex(32);

        or Crypt::SysRandom's `random_bytes`. When the hash is a cache key or
        a unique file name with no security role, suppress the violation:
        `# puff: ignore S010`. There is no fix.
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
            elsif ( $token->isa('PPI::Token::Symbol') && $PID_VARIABLE{ $token->content } ) {
                $found{'$$'} = 1;
            }
            elsif ( $token->isa('PPI::Token::Word') ) {
                my $word = $token->content =~ s/\A(?:CORE|Time::HiRes|Scalar::Util)::(?=\w+\z)//r;
                $found{$word} = 1 if $GUESSABLE{$word} && is_builtin_call($token);
            }
            elsif ( ( $token->isa('PPI::Token::Quote::Double') || $token->isa('PPI::Token::Quote::Interpolate') )
                && $token->string =~ $PID_IN_STRING ) {
                $found{'$$'} = 1;
            }
        }
    }
    return unless %found;
    my $sources = join '/', sort keys %found;
    return $self->violation(
        $elem,
        message => "$name of $sources is predictable (CWE-340); use random_bytes from Crypt::PRNG or Crypt::SysRandom"
    );
}

1;

# ABSTRACT: S010 - do not hash the time, PID or rand to make a token

__END__

=pod

=head1 DESCRIPTION

Reports md2, md4, md5, sha* and C<digest_data> digest functions whose
arguments include the time, the process ID, C<rand> or C<refaddr>. There is no
fix. Covers L<Perl::Critic::Policy::Security::RandBytesFromHash>, except that
a C<join> on its own is not reported.

=cut
