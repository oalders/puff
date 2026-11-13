package Puff::Rule::Security::ShellCommand;

use v5.36;
use parent 'Puff::Rule';

use Puff::PPIUtil qw( is_builtin_call call_args is_constant_string command_body $PERL_SHELL_META shell_first_word );

my %SHELL_FUNCTION = map { $_ => 1 } qw( system exec readpipe CORE::system CORE::exec CORE::readpipe );
my %SYSTEM         = map { $_ => 1 } qw( system CORE::system );
my %LIST_FUNCTION  = map { $_ => 1 } qw( system exec CORE::system CORE::exec );

my $VARIABLE = qr/\A[\$\@]\w+(?:::\w+)*\z/;

sub code       {'S008'}
sub summary    {'Do not pass a command built at runtime to the shell'}
sub cwe        {78}
sub fix_safety {'unsafe'}

sub applies_to {
    return [ 'PPI::Token::Word', 'PPI::Token::QuoteLike::Backtick', 'PPI::Token::QuoteLike::Command' ];
}

sub explanation {
    return <<~'END';
        When system, exec, backticks, qx or a piped open get the whole command
        as one string, Perl hands it to /bin/sh whenever it contains shell
        metacharacters. A value inside that string such as `x; rm -rf ~` or
        `$(curl evil)` then runs as a command of its own (CWE-78).

        The rule reports:

        - `system`, `exec` and `readpipe` with a single argument that is not a
          constant string: an interpolating string (`system("tar xf $file")`),
          a concatenation, or a scalar variable (`system($cmd)`);
        - backticks and `qx{...}` that interpolate a variable;
        - three-argument `open` with mode `-|` or `|-` and one command string
          that is not constant.

        Pass the program and its arguments as a list, which skips the shell:

            system( 'tar', 'xf', $file ) == 0 or die "tar failed: $?";
            open( my $fh, '-|', 'git', 'log', $ref ) or die $!;

        For captured output, use IPC::Run3, IPC::System::Simple's capturex
        or Capture::Tiny around the list form of system. `system { $prog }
        @args` and `system(@cmd)` are not reported. Two-argument piped opens
        are reported by S002.
        A constant command string with shell syntax is reported by S018,
        which is selected only by its code.

        A leading 0 or 1 is the Win32 spawn mode (0 waits, 1 spawns
        asynchronously), so the call is judged by the arguments after it. On
        Unix it would run a program named after the number.

        On Win32 the child gets one command line and parses it itself, so the
        list form is emulated and some quoting problems survive it. `system
        LIST` also falls back to the shell if the first spawn fails, so only
        `system { $prog } @args` reliably avoids the shell there (perlfunc).

        A lone program path that may contain spaces (`system $path`) should
        be written `system { $path } $path`; parentheses change nothing.

        The fix rewrites `system "tar -czf $out $src"` as `system 'tar',
        '-czf', $out, $src`, for `system` and `exec` (with or without a spawn
        mode) whose argument is one "..." or `qq{...}` string. It splits the
        string on spaces: a plain word becomes a '...' string, a whole `$var`
        or `@array` the bare variable, and a word mixing text and variables
        stays a "..." string. It declines when the string has fewer than two
        words, whitespace other than spaces, a shell metacharacter other than
        the `$` of a simple variable (so `${x}`, `$h{k}`, quotes, backslashes
        and `2>&1` are declined), a first word of `.` or `exec`, a leading
        `VAR=` assignment, or an `@` anywhere but a whole `@array` word.
        Declined calls are reported as not fixable.

        The fix is unsafe because it changes behaviour:
        - a variable holding several words (`my $opts = '-v -n'`) arrives as
          one argument instead of being split;
        - an empty or undef variable arrives as an empty argument instead of
          vanishing;
        - shell syntax inside a value (a glob, redirect or pipe) is no longer
          interpreted.

        Ruff's equivalents are S602, S605 and S607.
        END
}

sub check ( $self, $elem, $doc ) {
    if ( $elem->isa('PPI::Token::QuoteLike') ) {
        my ( undef, $interpolates ) = command_body($elem);
        return unless $interpolates;
        return $self->violation(
            $elem,
            message => 'Interpolated command runs through the shell (CWE-78); use the list form of system or IPC::Run3',
            fixable => 0,
        );
    }

    my $name = $elem->content;
    if ( $SHELL_FUNCTION{$name} && is_builtin_call($elem) ) {
        my $next = $elem->snext_sibling;
        return if $next && $next->isa('PPI::Structure::Block');
        my $args = _command_args($elem);
        return unless @$args == 1 && _is_shell_string( $args->[0] );
        ( my $short = $name ) =~ s/\ACORE:://;
        return $self->violation(
            $elem,
            message => "$short with one string runs it through the shell (CWE-78); pass the command as a list",
            fixable => $LIST_FUNCTION{$name} && defined _replacement( $args->[0] ) ? 1 : 0,
        );
    }

    if ( $name eq 'open' && is_builtin_call($elem) ) {
        my $args = call_args($elem);
        return unless @$args == 3 && @{ $args->[1] } == 1 && is_constant_string( $args->[1][0] );

        # /a: perl takes only ASCII whitespace around an open mode
        return unless $args->[1][0]->string =~ /\A\s*(?:-\||\|-)\s*\z/a;
        return unless _is_shell_string( $args->[2] );
        return $self->violation(
            $elem,
            message =>
                'Piped open with one command string runs it through the shell (CWE-78); pass the command as a list',
            fixable => 0,
        );
    }
    return;
}

sub fix ( $self, $violation, $fix ) {
    my $elem = $violation->element;
    return 0 unless $elem->isa('PPI::Token::Word') && $LIST_FUNCTION{ $elem->content };
    my $args = _command_args($elem);
    return 0 unless @$args == 1;
    my $text = _replacement( $args->[0] ) // return 0;
    $fix->replace( $args->[0][0], $text );
    return 1;
}

# The call's arguments without a Win32 spawn mode: a leading 0 or 1 is that,
# not the program.
sub _command_args ($word) {
    my $args = call_args($word);
    shift @$args
        if $SYSTEM{ $word->content }
        && @$args > 1
        && @{ $args->[0] } == 1
        && $args->[0][0]->isa('PPI::Token::Number')
        && ( $args->[0][0]->literal // q{} ) =~ /\A[01]\z/;
    return $args;
}

# The list that replaces the call's only argument (its significant elements),
# or undef unless Perl would split the string into the same words
# without the shell: one "..." or qq{} string of words separated by spaces,
# whose only shell metacharacter is the $ of a variable.
sub _replacement ($arg) {
    return unless @$arg == 1;
    my ($token) = @$arg;
    return unless $token->isa('PPI::Token::Quote::Double') || $token->isa('PPI::Token::Quote::Interpolate');
    my $body = $token->string;

    # Perl splits on tabs too, and a newline is shell syntax
    return if $body =~ /[^\S ]/a;
    return if grep { $_ ne '$' } $body =~ /($PERL_SHELL_META)/g;
    return if defined shell_first_word($body);

    # "$ x" interpolates $x, so it must not be split at that space
    return if $body =~ /\$(?!\w)/;

    # Not split ' ': it splits on U+00A0 in a character string and Perl does not
    my @words = split / +/, $body =~ s/\A +| +\z//gr;
    return unless @words >= 2;

    # An array in a word is joined and then split, so only a whole @array survives
    return if grep { /\@/ && !/$VARIABLE/ } @words;

    return join ', ', map { !/[\$\@]/ ? "'$_'" : /$VARIABLE/ ? $_ : qq{"$_"} } @words;
}

# One argument that the shell may see: anything but a constant string or an
# array.
sub _is_shell_string ($arg) {
    return 0 unless @$arg;
    my $first = $arg->[0];
    return 0 if @$arg == 1                        && is_constant_string($first);
    return 0 if $first->isa('PPI::Token::Symbol') && $first->raw_type eq '@' && @$arg == 1;
    return 0 if $first->isa('PPI::Token::Cast')   && $first->content eq '@';
    return 0 if $first->isa('PPI::Token::ArrayIndex');
    return 1;
}

1;

# ABSTRACT: S008 - do not pass a command built at runtime to the shell

__END__

=pod

=head1 DESCRIPTION

Reports one-string C<system>, C<exec> and C<readpipe> calls, interpolating
backticks and C<qx>, and three-argument piped opens with one command string
that is not constant. A leading 0 or 1 in C<system> is the Win32 spawn mode
(0 waits, 1 spawns asynchronously), so the arguments after it are judged.

The unsafe fix splits a C<system> or C<exec> string of plain words and
simple variables into a list, so C<system "tar -czf $out $src"> becomes
C<system 'tar', '-czf', $out, $src>. It declines a string with other shell
syntax, whitespace other than spaces or a single word. It is unsafe because
a variable is no longer split into words, an empty one becomes an empty
argument, and shell syntax in a value is no longer interpreted.

=cut
