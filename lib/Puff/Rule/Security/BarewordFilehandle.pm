package Puff::Rule::Security::BarewordFilehandle;

use v5.36;
use parent 'Puff::Rule';

use Puff::PPIUtil qw( is_builtin_call call_args );
use Scalar::Util  qw( refaddr );

my %OPENER   = map { $_ => 1 } qw( open opendir sysopen socket );
my %FIXABLE  = map { $_ => 1 } qw( open opendir sysopen );
my %EXCLUDED = map { $_ => 1 } qw( STDIN STDOUT STDERR DATA ARGV ARGVOUT _ my our local state );
my %MODIFIER = map { $_ => 1 } qw( if unless while until for foreach );
my %PRINT    = map { $_ => 1 } qw( print printf say );
my %HANDLE_FIRST = map { $_ => 1 } qw(
    close eof binmode fileno flock seek tell truncate read sysread syswrite
    readdir closedir rewinddir telldir seekdir
);

# Never chosen as the variable name: my $a or my $b would hide sort's.
my %RESERVED_VAR = map { $_ => 1 } qw( a b );

sub code       {'S003'}
sub summary    {'Use a lexical filehandle instead of a bareword'}
sub applies_to {'PPI::Token::Word'}
sub fix_safety {'unsafe'}
sub cwe        {1108}

sub explanation {
    return <<~'END';
        A bareword filehandle such as `open(FH, '<', $file)` is a package
        global. Any code in the same package can read from, write to or close
        it, a second open of the same name anywhere silently closes the first,
        and it is not closed when it goes out of scope. A lexical filehandle
        (`open(my $fh, '<', $file)`) is private to its scope and is closed
        automatically when the last reference to it goes away.

        Reported: open, opendir, sysopen and socket whose first argument is a
        bareword other than STDIN, STDOUT, STDERR, DATA, ARGV, ARGVOUT or _.

        The fix rewrites the first argument as `my $name` (the bareword in
        lower case, or with `_fh`, `_fh2`, ... appended when that variable
        name already appears in the file) and renames every use of the handle
        after the open in the same block: `<FH>`, `print FH ...` (which
        becomes `print {$fh} ...`), `print {FH} ...`, and the first argument
        of close, eof, binmode, fileno, flock, seek, tell, truncate, read,
        sysread, syswrite, readdir, closedir, rewinddir, telldir and seekdir.
        It declines, and the violation is reported as not fixable, for socket;
        when the open is not at the start of its own statement, is part of a
        condition or has a statement modifier (`if`, `for`, ...); when the
        handle is used in the open's own statement (`open(...) and print FH`);
        when the file opens the same name more than once, or another handle
        whose name differs only in case (LOG and Log); when `print FH`,
        `printf FH` or `say FH` has nothing to print after the handle
        (`print FH;`, `print FH if $x`, `{ print FH }`); when the name is used before
        the open, outside the open's block, in a different named sub, after a
        package statement, or in any other way (passed to a sub, select,
        file tests, write, `*FH` globs, a package-qualified name, or the name
        appearing inside any string, which could be a string eval or a
        symbolic reference).

        The fix is unsafe because it changes behaviour: the handle is now
        closed when its scope ends, and code elsewhere (another file, a
        string eval, a symbolic reference) that used the global handle no
        longer sees it.
        END
}

sub check ( $self, $elem, $doc ) {
    my $handle = _handle($elem) or return;
    return $self->violation(
        $elem,
        message => 'Bareword filehandle ' . $handle->content . '; use a lexical filehandle',
        fixable => defined _edits( $elem, $handle ) ? 1 : 0,
    );
}

sub fix ( $self, $violation, $fix ) {
    my $word   = $violation->element;
    my $handle = _handle($word) or return 0;
    my $edits  = _edits( $word, $handle ) // return 0;
    for my $edit (@$edits) {
        my ( $token, $text ) = @$edit;
        if ( $token->isa('PPI::Token::QuoteLike::Readline') ) {
            my $start = $fix->source->start_of($token) + 1;    # after the <
            $fix->replace_range( $start, $start + length $handle->content, $text );
        }
        else {
            $fix->replace( $token, $text );
        }
    }
    return 1;
}

# The bareword first argument of an open/opendir/sysopen/socket call, or
# undef when $word is not such a call.
sub _handle ($word) {
    return unless $OPENER{ $word->content } && is_builtin_call($word);
    my $args = call_args($word);
    return unless @$args && @{ $args->[0] } == 1;
    my ($first) = @{ $args->[0] };
    return unless $first->isa('PPI::Token::Word') && !$EXCLUDED{ $first->content };
    return $first;
}

# A list of [token, replacement text] pairs that rename the handle (for a
# Readline token the text replaces just the name inside the angle
# brackets), or undef when the fix should decline.
sub _edits ( $word, $handle ) {
    return unless $FIXABLE{ $word->content };
    my $name = $handle->content;
    return unless $name =~ /\A[A-Za-z_]\w*\z/;

    my $statement = $word->parent;
    return unless ref $statement eq 'PPI::Statement';
    return unless _same_element( scalar $statement->schild(0), $word );
    return if grep { $_->isa('PPI::Token::Word') && $MODIFIER{ $_->content } } $statement->schildren;
    my $scope = $statement->parent;
    return unless $scope && ( $scope->isa('PPI::Structure::Block') || $scope->isa('PPI::Document') );

    my $doc  = $word->top;
    my $text = $doc->serialize;
    return if $text =~ /\*\{?\s*(?:\w*::)*\Q$name\E\b/;

    my @calls = grep { _handle($_) } @{ $doc->find('PPI::Token::Word') || [] };
    my @opens = grep { $FIXABLE{ $_->content } && _handle($_)->content eq $name } @calls;
    return unless @opens == 1;

    # open(LOG, ...) and open(Log, ...) would both become my $log
    return if grep { my $other = _handle($_)->content; $other ne $name && lc $other eq lc $name } @calls;

    my $var      = _var_name( $text, $name ) // return;
    my $open_sub = _enclosing_sub($word);
    my @edits    = ( [ $handle, "my \$$var" ] );
    my ( $after_open, $package_since_open );

    for my $token ( $doc->tokens ) {
        if ( refaddr($token) == refaddr($handle) ) {
            $after_open = 1;
            next;
        }
        if ( $token->isa('PPI::Token::Word') ) {
            my $content = $token->content;
            $package_since_open = 1
                if $after_open && $content eq 'package' && $token->parent->isa('PPI::Statement::Package');
            return if $content =~ /(?:::|')\Q$name\E\z/;
            next unless $content eq $name;
        }
        elsif ( $token->isa('PPI::Token::QuoteLike::Readline') && $token->content eq "<$name>" ) {

            # a use, checked below
        }
        elsif ( _is_string($token) ) {
            return if _string_text($token) =~ /\b\Q$name\E\b/;
            next;
        }
        else {
            next;
        }

        return unless $after_open && !$package_since_open;
        return unless _inside( $token, $scope );
        return if _inside( $token, $statement );
        return unless _same_element( scalar _enclosing_sub($token), $open_sub );

        if ( $token->isa('PPI::Token::QuoteLike::Readline') ) {
            push @edits, [ $token, "\$$var" ];
            next;
        }
        my $replacement = _word_use( $token, $var ) // return;
        push @edits, [ $token, $replacement ];
    }
    return \@edits;
}

sub _same_element ( $x, $y ) {
    return ( refaddr($x) // 0 ) == ( refaddr($y) // 0 );
}

sub _is_string ($token) {
    return $token->isa('PPI::Token::Quote')
        || $token->isa('PPI::Token::QuoteLike')
        || $token->isa('PPI::Token::HereDoc');
}

sub _string_text ($token) {
    return $token->isa('PPI::Token::HereDoc') ? join( '', $token->heredoc ) : $token->content;
}

# The replacement for a bareword use of the handle, or undef when the use is
# not one the fix recognises.
sub _word_use ( $token, $var ) {
    my $prev = $token->sprevious_sibling;
    my $next = $token->snext_sibling;

    # print FH LIST; without a LIST, `print {$fh};` would not compile
    if ( $prev && _is_print($prev) ) {
        return unless $next;
        return if $next->isa('PPI::Token::Operator') || $next->isa('PPI::Structure::List');
        return if $next->isa('PPI::Token::Structure');
        return if $next->isa('PPI::Token::Word') && $MODIFIER{ $next->content };
        return "{\$$var}";
    }

    # print {FH} ...
    my $parent = $token->parent;
    if ( !$prev && !$next && ref $parent eq 'PPI::Statement' ) {
        my $block = $parent->parent;
        return unless $block->isa('PPI::Structure::Block') && $block->schildren == 1;
        my $before = $block->sprevious_sibling;
        return unless $before && _is_print($before);
        return "\$$var";
    }

    # close FH / close(FH) and friends
    my $function = $prev;
    if ( !$function && $parent->isa('PPI::Statement::Expression') ) {
        my $list = $parent->parent;
        $function = $list->sprevious_sibling if $list && $list->isa('PPI::Structure::List');
    }
    return unless $function && $function->isa('PPI::Token::Word') && $HANDLE_FIRST{ $function->content };
    return unless is_builtin_call($function);
    my $args = call_args($function);
    return unless @$args && @{ $args->[0] } == 1 && refaddr( $args->[0][0] ) == refaddr($token);
    return "\$$var";
}

sub _is_print ($elem) {
    return $elem->isa('PPI::Token::Word') && $PRINT{ $elem->content } && is_builtin_call($elem);
}

sub _inside ( $elem, $scope ) {
    for ( my $p = $elem->parent; $p; $p = $p->parent ) {
        return 1 if refaddr($p) == refaddr($scope);
    }
    return 0;
}

sub _enclosing_sub ($elem) {
    for ( my $p = $elem->parent; $p; $p = $p->parent ) {
        return $p if $p->isa('PPI::Statement::Sub');
    }
    return;
}

sub _var_name ( $text, $name ) {
    my $base = lc $name;
    for my $n ( 0 .. 1000 ) {
        my $candidate = $n == 0 ? $base : $n == 1 ? "${base}_fh" : "${base}_fh$n";
        next if $RESERVED_VAR{$candidate};
        return $candidate unless $text =~ /[\$\@\%]\{?\Q$candidate\E\b/;
    }
    return;
}

1;

# ABSTRACT: S003 - Use a lexical filehandle instead of a bareword

__END__

=pod

=head1 DESCRIPTION

Reports calls to the built-in C<open>, C<opendir>, C<sysopen> and C<socket>
whose first argument is a bareword other than the standard handles.

The unsafe fix (not for C<socket>) rewrites the bareword as C<my $name> and
renames each use of the handle after the open in the same block: C<E<lt>FHE<gt>>,
C<print FH>, C<print {FH}> and the first argument of C<close>, C<eof>,
C<binmode> and similar functions. Any other use, or a use it cannot be sure
of, makes it decline, and the violation is reported with C<fixable> 0.

=cut
