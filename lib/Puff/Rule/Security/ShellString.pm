package Puff::Rule::Security::ShellString;

use v5.36;
use parent 'Puff::Rule';

use Puff::PPIUtil qw( is_builtin_call call_args is_constant_string );

my %LIST_FUNCTION = map { $_ => 1 } qw( system exec CORE::system CORE::exec );
my %PIPE_FUNCTION = map { $_ => 1 } qw( readpipe CORE::readpipe );
my $INTERPOLATES  = qr/(?<!\\)(?:\\\\)*[\$\@]/;

# Perl hands a one-string command to /bin/sh when it contains one of these
# (doio.c), or when its first word is `.`, `exec` or a VAR= assignment.
my $PERL_SHELL_META = qr/[\$&*(){}\[\]'";\\|?<>~`\n]/;

# A word that is safe to pass as a list element unchanged.
my $PLAIN_WORD = qr/\A[A-Za-z0-9_.\/:=+,@%-]+\z/;

my $CAPTURE = 'use IPC::Run3 or Capture::Tiny with a list';

sub code            {'S018'}
sub summary         {'Pass system/exec a list instead of one command string'}
sub applies_to      { [ 'PPI::Token::Word', 'PPI::Token::QuoteLike::Backtick', 'PPI::Token::QuoteLike::Command' ] }
sub fix_safety      {'unsafe'}
sub cwe             {78}
sub explicit_select {1}

sub explanation {
    return <<~'END';
        `system`, `exec`, backticks, `qx` and `readpipe` given the whole
        command as one string hand it to /bin/sh when it contains shell
        syntax (pipes, redirects, globs, quotes, `&&`, `;`, ...). Without
        shell syntax Perl splits it on whitespace itself, so the string form
        only hides where the argument boundaries are; the list form makes
        them explicit and never involves the shell (CWE-78).

        The rule reports a constant string (no interpolation) that is more
        than one plain word:

        - `system` or `exec` with that string as their only argument;
        - `readpipe`, backticks and `qx` with that command.

        A command built at runtime (`system("ls $dir")`, `system($cmd)`,
        interpolating backticks) is S008's; this rule leaves it alone, so a
        call is never reported by both. `system 'ls'` (one word, no shell
        syntax) is not reported: it already skips the shell. Neither are the
        list forms, `system { $prog } @args`, or `system(@cmd)`.

        The unsafe fix rewrites `system 'ls -l /tmp'` as
        `system 'ls', '-l', '/tmp'`. It applies only to `system` and `exec`
        when every word is made of `A-Za-z0-9_./:=+,@%-` and the first word
        is not `.`, `exec` or a `VAR=value` assignment, so the string has no
        shell syntax and the list runs the same program with the same
        arguments. Commands with shell syntax are reported but not fixed:
        rewrite them by hand, running the pipeline in Perl or with IPC::Run3.
        For backticks, `qx` and `readpipe`, capture output with IPC::Run3 or
        Capture::Tiny around the list form of system; they are not fixed.
        It is unsafe because the string form falls back to /bin/sh when the
        program cannot be executed directly (a script with no `#!` line),
        and the list form does not.

        This rule is selected only by its code or `ALL`, not by `S`.
        END
}

sub check ( $self, $elem, $doc ) {
    if ( $elem->isa('PPI::Token::QuoteLike') ) {
        my ( $delim, $body ) = $elem->content =~ /\A(?:qx\s*(.)|`)(.*)\z/s;
        return unless defined $body;

        # S008 reports the ones that interpolate.
        $body =~ s/.\z//s;                                                           # closing delimiter
        return if !( defined $delim && $delim eq q{'} ) && $body =~ $INTERPOLATES;
        return unless _needs_list($body);
        return $self->violation( $elem, fixable => 0, message => _message( 'Command', $body, $CAPTURE ) );
    }

    my ( $name, $string ) = _call($elem) or return;
    return unless _needs_list($string);
    ( my $short = $name ) =~ s/\ACORE:://;

    if ( $PIPE_FUNCTION{$name} ) {
        return $self->violation( $elem, fixable => 0, message => _message( $short, $string, $CAPTURE ) );
    }
    return $self->violation(
        $elem,
        fixable => _plain_words($string) ? 1 : 0,
        message => _message( $short, $string, 'pass the command as a list' ),
    );
}

sub _message ( $what, $string, $advice ) {
    return _runs_shell($string)
        ? "$what with shell syntax in one string runs /bin/sh (CWE-78); $advice"
        : "$what given as one string; $advice";
}

sub fix ( $self, $violation, $fix ) {
    my $elem = $violation->element;
    my ( $name, $string, $token ) = _call($elem) or return 0;
    return 0 unless $LIST_FUNCTION{$name};
    my $words = _plain_words($string) or return 0;
    $fix->replace( $token, join ', ', map {"'$_'"} @$words );
    return 1;
}

# ( name, string, token ) for a system, exec or readpipe call whose only
# argument is one constant string literal.
sub _call ($elem) {
    my $name = $elem->content;
    return unless $LIST_FUNCTION{$name} || $PIPE_FUNCTION{$name};
    return unless is_builtin_call($elem);
    my $next = $elem->snext_sibling;
    return if $next && $next->isa('PPI::Structure::Block');
    my $args = call_args($elem);
    return unless @$args == 1 && @{ $args->[0] } == 1;
    my $token = $args->[0][0];
    return if $token->isa('PPI::Token::HereDoc');
    return unless is_constant_string($token);
    return ( $name, $token->string, $token );
}

# Whether a constant command is anything but a single plain word.
sub _needs_list ($string) {
    return 1 if _runs_shell($string);
    my @words = split q{ }, $string;
    return 0 unless @words;
    return 1 if @words > 1;
    return $words[0] =~ $PLAIN_WORD ? 0 : 1;
}

# The words of a command that Perl would run without the shell and whose
# words can be passed as a list unchanged, or undef.
sub _plain_words ($string) {
    return if _runs_shell($string);
    my @words = split q{ }, $string;
    return unless @words > 1;
    return if grep { $_ !~ $PLAIN_WORD } @words;
    return if $words[0] =~ /=/;
    return \@words;
}

sub _runs_shell ($string) {
    return 1 if $string =~ $PERL_SHELL_META;
    my ($first) = split q{ }, $string;
    return 0 unless defined $first;
    return 1 if $first eq '.' || $first eq 'exec' || $first =~ /\A\w*=/;
    return 0;
}

1;

# ABSTRACT: S018 - pass system/exec a list instead of one command string

__END__

=pod

=head1 DESCRIPTION

Reports C<system>, C<exec>, C<readpipe>, backticks and C<qx> given a
constant command string of more than one plain word. The unsafe fix splits
a C<system> or C<exec> string with no shell syntax into a list of words.

=head1 BOUNDARY WITH S008

S008 (L<Puff::Rule::Security::ShellCommand>) reports a one-string command
built at runtime: an interpolating string, a concatenation or a variable.
Those cannot be split into a list mechanically without knowing what the
interpolated values hold, so S008 has no fix. This rule takes the other
half: constant strings, where the words are visible in the source and the
list form can be written for the reader. The two never report the same
call. This rule is selected only by its exact code, because a constant
command without shell syntax is a style issue more than a hole.

=cut
