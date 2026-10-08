package Puff::Rule::Security::InsecureTempFile;

use v5.36;
use parent 'Puff::Rule';

use Puff::PPIUtil qw( is_builtin_call );

my %NAME_ONLY = map { $_ => 1 } qw( mktemp tmpnam tempnam );
my %QUALIFIED = map { $_ => 1 } qw(
    File::Temp::mktemp File::Temp::tmpnam File::Temp::tempnam POSIX::tmpnam
);

sub code       {'S007'}
sub summary    {'Do not build a temporary file name yourself'}
sub applies_to { [ 'PPI::Token::Word', 'PPI::Token::Quote' ] }
sub options    { { 'tmp-directories' => [ '/tmp', '/var/tmp', '/dev/shm' ] } }
sub cwe        {377}

sub explanation {
    return <<~'END';
        A temporary file whose name can be guessed lets another user on the
        machine create that file, or a symlink with that name, before your
        program opens it (CWE-377). Your program then writes to a file they
        control, or overwrites a file they point it at.

        The rule reports:

        - a string literal that names a file in /tmp, /var/tmp or /dev/shm,
          such as `"/tmp/report.$$"`, or that is `'/tmp/'` followed by `.`
          (concatenation);
        - calls to mktemp, tmpnam and tempnam (File::Temp's or POSIX's), which
          return a name but do not create the file, so the same race applies.

        A directory on its own (`'/tmp'`, `DIR => '/tmp'`) is not reported.
        Heredocs, `catfile('/tmp', $name)` and `path('/tmp')->child($name)`
        are not checked.

        Use File::Temp, which creates the file with O_EXCL and a random name:

            use File::Temp qw( tempfile );
            my ( $fh, $filename ) = tempfile();

        or `File::Temp->new`, or Path::Tiny's `tempfile`. There is no fix.

        To change the directories, list them in .puff.toml:

            [rules.S007]
            tmp-directories = ["/tmp", "/var/tmp", "/dev/shm", "/scratch"]

        Ruff's equivalents are S108 and S306.
        END
}

sub new ( $class, %args ) {
    my $self = $class->SUPER::new(%args);
    my $dirs = $self->option('tmp-directories');
    die "rules.S007.tmp-directories must be a list of absolute paths\n"
        unless ref $dirs eq 'ARRAY' && !grep { !defined || ref || !m{\A/} } @$dirs;
    my $alt = join '|', map { quotemeta s{/+\z}{}r } @$dirs;
    $self->{tmp_file} = @$dirs ? qr{\A(?:$alt)/(.?)}s : qr/(?!)/;
    return $self;
}

sub check ( $self, $elem, $doc ) {
    return $self->_check_quote($elem) if $elem->isa('PPI::Token::Quote');

    my $name = $elem->content;
    if ( $QUALIFIED{$name} || ( $NAME_ONLY{$name} && is_builtin_call($elem) && _is_call($elem) ) ) {
        return $self->violation( $elem,
            message => "$name returns a file name without creating the file (CWE-377); use File::Temp's tempfile" );
    }
    return;
}

sub _check_quote ( $self, $quote ) {
    my ($rest) = $quote->string =~ $self->{tmp_file} or return;
    if ( $rest eq '' ) {
        my $next = $quote->snext_sibling;
        return unless $next && $next->isa('PPI::Token::Operator') && $next->content eq '.';
    }
    return $self->violation( $quote,
        message => 'Predictable temporary file name (CWE-377); use File::Temp' );
}

# A bare mktemp(...) or mktemp $x, not a hash key, sub name or method.
sub _is_call ($word) {
    my $parent = $word->parent;
    return 0 if $parent && $parent->isa('PPI::Statement::Include');
    my $next = $word->snext_sibling;
    return 0 unless $next;
    return 0 if $next->isa('PPI::Token::Operator') && $next->content ne '-';
    return 0 if $next->isa('PPI::Token::Structure');
    return 1;
}

1;

# ABSTRACT: S007 - do not build a temporary file name yourself

__END__

=pod

=head1 DESCRIPTION

Reports string literals naming a file in a shared temporary directory, and
calls to C<mktemp>, C<tmpnam> and C<tempnam>. There is no fix.

=cut
