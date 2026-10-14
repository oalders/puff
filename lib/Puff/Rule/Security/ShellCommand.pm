package Puff::Rule::Security::ShellCommand;

use v5.36;
use parent 'Puff::Rule';

use Puff::PPIUtil qw( is_builtin_call call_args is_constant_string command_body );

my %SHELL_FUNCTION = map { $_ => 1 } qw( system exec readpipe CORE::system CORE::exec CORE::readpipe );
my %SYSTEM         = map { $_ => 1 } qw( system CORE::system );

sub code    {'S008'}
sub summary {'Do not pass a command built at runtime to the shell'}
sub cwe     {78}

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
        are reported by S002. There is no fix.
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

        Ruff's equivalents are S602, S605 and S607.
        END
}

sub check ( $self, $elem, $doc ) {
    if ( $elem->isa('PPI::Token::QuoteLike') ) {
        my ( undef, $interpolates ) = command_body($elem);
        return unless $interpolates;
        return $self->violation(
            $elem,
            message => 'Interpolated command runs through the shell (CWE-78); use the list form of system or IPC::Run3'
        );
    }

    my $name = $elem->content;
    if ( $SHELL_FUNCTION{$name} && is_builtin_call($elem) ) {
        my $next = $elem->snext_sibling;
        return if $next && $next->isa('PPI::Structure::Block');
        my $args = call_args($elem);

        # Win32 takes a leading 0 or 1 as the spawn mode, not the program
        shift @$args
            if $SYSTEM{$name}
            && @$args > 1
            && @{ $args->[0] } == 1
            && $args->[0][0]->isa('PPI::Token::Number')
            && ( $args->[0][0]->literal // q{} ) =~ /\A[01]\z/;
        return unless @$args == 1 && _is_shell_string( $args->[0] );
        ( my $short = $name ) =~ s/\ACORE:://;
        return $self->violation(
            $elem,
            message => "$short with one string runs it through the shell (CWE-78); pass the command as a list"
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
                'Piped open with one command string runs it through the shell (CWE-78); pass the command as a list'
        );
    }
    return;
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
There is no fix.

=cut
