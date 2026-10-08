package Puff::Rule::Bugs::TryTinySemicolon;

use v5.36;
use parent 'Puff::Rule';

sub code       {'B005'}
sub summary    {'Try::Tiny try/catch is not ended with a semicolon'}
sub applies_to {'PPI::Token::Word'}
sub fix_safety {'unsafe'}
sub options    { { modules => [ 'Try::Tiny', 'Try::Catch' ] } }

sub explanation {
    return <<~'END';
        Try::Tiny's `try`, `catch` and `finally` are functions that take
        blocks, not syntax, so the whole construct is one statement and
        needs a semicolon after the last block. Without one, the next line
        becomes more arguments to `try`:

            try { risky() } catch { warn $_ }
            return cleanup();    # runs first, and try never runs

        Try::Tiny dies when it sees an unexpected argument, but not when
        the next line returns an empty list or leaves the sub, so the bug
        can go unnoticed.

        The rule reports a `try` whose last `catch` or `finally` block is
        followed by more code instead of `;`, in a file that loads
        Try::Tiny or Try::Catch. A try at the end of a block, or followed by
        a statement modifier (`try { } catch { } if $x;`) or an operator, is
        not reported. Files that use the `try` feature,
        Syntax::Keyword::Try or TryCatch are not affected: there `try` is
        syntax and needs no semicolon.

        The fix adds the semicolon. It is unsafe because the code that
        follows then runs after the try instead of before it.

        Option `modules` (default `["Try::Tiny", "Try::Catch"]`): modules
        whose `try` is a function. Add your own wrappers here.
        END
}

my %MODIFIER = map { $_ => 1 } qw( if unless while until for foreach );

sub check ( $self, $elem, $doc ) {
    return unless defined _unterminated($elem);
    return unless $self->_loads_try_module($doc);
    return $self->violation( $elem, message => 'try/catch is not ended with a semicolon; the next statement becomes arguments to try' );
}

sub fix ( $self, $violation, $fix ) {
    my $last = _unterminated( $violation->element ) // return 0;
    $fix->insert_after( $last, q{;} );
    return 1;
}

# The last block of a try/catch/finally that is followed by more code, or
# undef.
sub _unterminated ($try) {
    return unless $try->content eq 'try';
    my $prev = $try->sprevious_sibling;
    return if $prev && $prev->isa('PPI::Token::Operator') && $prev->content eq '->';
    my $block = $try->snext_sibling;
    return unless $block && $block->isa('PPI::Structure::Block');
    my $next = $block->snext_sibling;
    while ( $next && $next->isa('PPI::Token::Word') && ( $next->content eq 'catch' || $next->content eq 'finally' ) ) {
        my $catch_block = $next->snext_sibling;
        last unless $catch_block && $catch_block->isa('PPI::Structure::Block');
        $block = $catch_block;
        $next  = $block->snext_sibling;
    }
    return unless $next;
    return if $next->isa('PPI::Token::Structure') || $next->isa('PPI::Token::Operator');
    return if $next->isa('PPI::Token::Word') && $MODIFIER{ $next->content };
    return $block;
}

sub _loads_try_module ( $self, $doc ) {
    my %wanted = map { $_ => 1 } @{ $self->option('modules') };
    my $found  = $doc->find_first( sub ( $top, $el ) {
        $el->isa('PPI::Statement::Include') && ( $el->type // q{} ) eq 'use' && $wanted{ $el->module // q{} };
    } );
    return $found ? 1 : 0;
}

1;

# ABSTRACT: B005 - Try::Tiny try/catch is not ended with a semicolon

__END__

=pod

=head1 DESCRIPTION

Reports a Try::Tiny C<try>/C<catch>/C<finally> that is followed by more code
instead of a semicolon, which turns that code into arguments to C<try>. The
unsafe fix adds the semicolon.

Based on L<Perl::Critic::Policy::TryTiny::RequireBlockTermination>, limited
to files that load Try::Tiny or Try::Catch and to try blocks followed by more
code.

Selected by default, as part of C<B>.

=cut
