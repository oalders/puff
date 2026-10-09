package Puff::Rule::Security::ShellString;

use v5.36;
use parent 'Puff::Rule';

use Puff::PPIUtil qw( is_builtin_call call_args is_constant_string command_body );

my %LIST_FUNCTION = map { $_ => 1 } qw( system exec CORE::system CORE::exec );
my %PIPE_FUNCTION = map { $_ => 1 } qw( readpipe CORE::readpipe );

# Perl hands a one-string command to /bin/sh when it contains one of these
# (doio.c, do_exec3), except for a single newline at the very end, which it
# strips. It also does when the first word is `.` or `exec`, or the command
# starts with a VAR= assignment.
my $PERL_SHELL_META = qr/[\$&*(){}\[\]'";\\|?<>~`\n]/;

my $LIST    = 'pass the command and its arguments as a list';
my $CAPTURE = 'capture output with IPC::Run3 or Capture::Tiny and a list';

sub code            {'S018'}
sub summary         {'Constant command string runs /bin/sh'}
sub applies_to      { [ 'PPI::Token::Word', 'PPI::Token::QuoteLike::Backtick', 'PPI::Token::QuoteLike::Command' ] }
sub cwe             {78}
sub explicit_select {1}

sub explanation {
    return <<~'END';
        `system`, `exec`, backticks, `qx` and `readpipe` given the whole
        command as one string hand it to /bin/sh when it contains shell
        syntax: one of `$ & * ( ) { } [ ] ' " ; \ | ? < > ~` and backtick, a
        newline before the end, a first word of `.` or `exec`, or a leading
        `VAR=value` assignment. The shell then parses quoting, globs,
        variables, pipes and redirects, which is where injection and
        surprises come from (CWE-78).

        The rule reports a constant string (no interpolation) with shell
        syntax that is:

        - the only argument of `system` or `exec`;
        - the only argument of `readpipe`, or the command of backticks or
          `qx`.

        A string without shell syntax (`system 'ls -l /tmp'`) is not
        reported: Perl already skips the shell for it, splitting it on
        whitespace and running the program directly, so the list form would
        change nothing. A command built at runtime (`system("ls $dir")`,
        `system($cmd)`, interpolating backticks) is S008's; this rule leaves
        it alone, so a call is never reported by both. The list forms,
        `system { $prog } @args` and `system(@cmd)`, are not reported.

        There is no fix. The fix first proposed, splitting the string into a
        list of words, was dropped: without shell syntax the split changes
        nothing, and a string that runs the shell uses shell syntax, so
        splitting it into words would change what it does. Rewrite it by
        hand: run the program with a list of arguments and do the piping,
        redirection or globbing in Perl (IPC::Run3, Capture::Tiny, `glob`).

        On Win32 neither form is the POSIX one: the list form is joined back
        into a command line and Perl quotes the arguments by its own rules,
        so the list form and the string form differ in other ways there.

        This rule is selected only by its code or `ALL`, not by `S`.
        END
}

sub check ( $self, $elem, $doc ) {
    if ( $elem->isa('PPI::Token::QuoteLike') ) {
        my ( $body, $interpolates ) = command_body($elem);
        return if !defined $body || $interpolates;    # S008 reports the ones that interpolate
        $body = _unescape($body) unless $elem->content =~ /\Aqx\s*'/;
        my $syntax = _shell_syntax($body) // return;
        return $self->violation( $elem, message => _message( 'Command', $syntax, $CAPTURE ) );
    }

    my ( $name, $string ) = _call($elem) or return;
    my $syntax = _shell_syntax($string) // return;
    ( my $short = $name ) =~ s/\ACORE:://;
    return $self->violation(
        $elem,
        message => _message( "$short command", $syntax, $PIPE_FUNCTION{$name} ? $CAPTURE : $LIST ),
    );
}

sub _message ( $what, $syntax, $advice ) {
    return "$what string runs /bin/sh (shell syntax: $syntax); $advice";
}

# ( name, string ) for a system, exec or readpipe call whose only argument is
# one constant string literal or heredoc, possibly in extra parentheses.
sub _call ($elem) {
    my $name = $elem->content;
    return unless $LIST_FUNCTION{$name} || $PIPE_FUNCTION{$name};
    return unless is_builtin_call($elem);
    my $next = $elem->snext_sibling;
    return if $next && $next->isa('PPI::Structure::Block');

    my $args = call_args($elem);
    my @arg  = @$args == 1 ? @{ $args->[0] } : ();
    @arg = ($next) if !@$args && $next && $next->isa('PPI::Structure::List');    # system(( ... ))
    while ( @arg == 1 && $arg[0]->isa('PPI::Structure::List') ) {
        my @stmt = $arg[0]->schildren;
        last unless @stmt == 1 && $stmt[0]->isa('PPI::Statement');
        @arg = $stmt[0]->schildren;
    }
    return unless @arg == 1 && is_constant_string( $arg[0] );

    return ( $name, _string_value( $arg[0] ) );
}

# The value of a constant string token, with its escapes processed.
sub _string_value ($token) {
    if ( $token->isa('PPI::Token::HereDoc') ) {
        my $text = join q{}, $token->heredoc;
        return ( $token->{_mode} // q{} ) eq 'literal' ? $text : _unescape($text);
    }
    return $token->literal if $token->can('literal');    # '...' and q{...}
    return _unescape( $token->string );
}

# Processes the escapes of a double-quoted string with nothing interpolated,
# enough to tell which shell metacharacters the value holds.
sub _unescape ($text) {
    state %ESCAPE = ( n => "\n", t => "\t", r => "\r", f => "\f", a => "\a", e => "\e" );
    $text =~ s{\\(.)}{$ESCAPE{$1} // $1}gse;
    return $text;
}

# A short description of why Perl runs this command through /bin/sh, or
# undef when it runs the program directly.
sub _shell_syntax ($string) {
    ( my $cmd = $string )            =~ s/\A\s+//;
    return '. command' if $cmd       =~ /\A\.\s/;
    return 'exec command' if $cmd    =~ /\Aexec\s/;
    return 'VAR= assignment' if $cmd =~ /\A\w*=/;

    $cmd =~ s/\n\z//;
    my %seen;
    my @meta = grep { !$seen{$_}++ } $cmd =~ /($PERL_SHELL_META)/g;
    return unless @meta;
    return join q{ }, map { $_ eq "\n" ? 'newline' : $_ } @meta;
}

1;

# ABSTRACT: S018 - constant command string runs /bin/sh

__END__

=pod

=head1 DESCRIPTION

Reports C<system>, C<exec>, C<readpipe>, backticks and C<qx> given one
constant command string that Perl runs through /bin/sh: it has shell
metacharacters (as listed in F<doio.c>), a newline before the end, a first
word of C<.> or C<exec>, or a leading C<VAR=value> assignment. There is no
fix.

A constant string without shell syntax, such as C<system 'ls -l /tmp'>, is
not reported. Perl splits it on whitespace and runs the program directly,
so it never reaches the shell and the list form would change nothing.

Issue #17 also asked for a fix splitting the string into a list. It was
dropped: for a string without shell syntax the split changes nothing, since
Perl already does it, and a string that does run the shell uses shell
syntax (quotes, pipes, globs, redirects), so it cannot be split into a list
mechanically.

On Win32 the list form is joined back into a command line and Perl quotes
the arguments by its own rules, so the two forms are not equivalent in the
same way there.

=head1 BOUNDARY WITH S008

S008 (L<Puff::Rule::Security::ShellCommand>) reports a one-string command
built at runtime: an interpolating string, a concatenation or a variable.
This rule takes the constant ones. Both decide whether a backtick or C<qx>
command interpolates with C<command_body> from L<Puff::PPIUtil>, and whether
a call argument is constant with C<is_constant_string>, so the two never
report the same call. This rule is selected only by its exact code, because
a constant command cannot be injected into by itself; the report is about
avoiding the shell's parsing, not about untrusted input.

=cut
