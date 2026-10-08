package Puff::Rule::Security::InsecureTempFile;

use v5.36;
use parent 'Puff::Rule';

use Puff::PPIUtil qw( is_builtin_call );

my %NAME_ONLY = map { $_ => 1 } qw( mktemp tmpnam tempnam );
my %QUALIFIED = map { $_ => 1 } qw(
    File::Temp::mktemp File::Temp::tmpnam File::Temp::tempnam POSIX::tmpnam
);
my %DECLARATOR = map { $_ => 1 } qw( my our local state );

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
        - calls to mktemp and tempnam, and POSIX::tmpnam, which return a name
          but do not create the file, so the same race applies;
        - File::Temp's tmpnam in scalar context, where it also returns only a
          name: inside `scalar(...)`, next to an operator such as `.`, or
          assigned to a scalar (`my $name = tmpnam()`). In list context
          (`my ( $fh, $name ) = tmpnam()`) it creates the file safely and is
          not reported. Where the context is not clear from the code, such
          as `return tmpnam()`, it is not reported either.

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
    return unless $QUALIFIED{$name} || ( $NAME_ONLY{$name} && is_builtin_call($elem) && _is_call($elem) );
    return if $name =~ /(?:\A|File::Temp::)tmpnam\z/ && !_in_scalar_context($elem);
    return $self->violation( $elem,
        message => "$name returns a file name without creating the file (CWE-377); use File::Temp's tempfile" );
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
    return 1 unless $next;
    return 0 if $next->isa('PPI::Token::Operator') && $next->content !~ /\A(?:-|\.|,)\z/;
    return 0 if $next->isa('PPI::Token::Structure') && $next->content ne ';';
    return 1;
}

# True when the call is clearly in scalar context: `scalar(tmpnam())`,
# `scalar tmpnam`, next to an operator, or assigned to a scalar.
sub _in_scalar_context ($word) {
    my $end  = $word->snext_sibling;
    $end = $word unless $end && $end->isa('PPI::Structure::List');
    my $prev = $word->sprevious_sibling;
    my $next = $end->snext_sibling;

    if ( !$prev && $word->parent->isa('PPI::Statement::Expression') ) {
        my $list = $word->parent->parent;
        my $func = $list && $list->isa('PPI::Structure::List') && $list->sprevious_sibling;
        return 1 if $func && $func->isa('PPI::Token::Word') && $func->content eq 'scalar';
    }
    return 1 if $prev && $prev->isa('PPI::Token::Word') && $prev->content eq 'scalar';
    return 1 if _is_scalar_operator($next);
    return 0 unless $prev && $prev->isa('PPI::Token::Operator');
    return 1 if _is_scalar_operator($prev);
    return 0 unless $prev->content eq '=';

    my @lhs;
    for ( my $el = $prev->sprevious_sibling ; $el ; $el = $el->sprevious_sibling ) {
        last if $el->isa('PPI::Token::Operator') && $el->content ne '->';
        unshift @lhs, $el;
    }
    shift @lhs while @lhs && $lhs[0]->isa('PPI::Token::Word') && $DECLARATOR{ $lhs[0]->content };
    return 0 if !@lhs || grep { $_->isa('PPI::Structure::List') } @lhs;
    return $lhs[0]->isa('PPI::Token::Symbol') && $lhs[0]->content =~ /\A\$/;
}

# Any operator but list separators, plain assignment and the ternary forces
# scalar context on its operand.
sub _is_scalar_operator ($el) {
    return 0 unless $el && $el->isa('PPI::Token::Operator');
    return $el->content !~ m{\A(?:,|=>|=|->|\\|\?|:)\z};
}

1;

# ABSTRACT: S007 - do not build a temporary file name yourself

__END__

=pod

=head1 DESCRIPTION

Reports string literals naming a file in a shared temporary directory, and
calls to C<mktemp>, C<tmpnam> and C<tempnam>. There is no fix.

=cut
