package Puff::Engine;

use v5.36;

use List::Util         qw( min );
use PPI                ();
use Puff::Edits        ();
use Puff::Fix          ();
use Puff::Source       ();
use Puff::Suppressions ();
use Puff::Violation    ();
use Scalar::Util       qw( blessed refaddr );

my $MAX_PASSES   = 10;
my $P001_SUMMARY = 'suppression comment must list codes';

sub new ( $class, %args ) {
    return bless {
        rules    => $args{rules}    // [],
        fix_mode => $args{fix_mode} // 'none',
    }, $class;
}

sub builtin_rules_info ($class) {
    return ( { code => 'P001', summary => $P001_SUMMARY } );
}

sub process_source ( $self, $src, %args ) {
    my $file   = $args{file};
    my %result = ( violations => [], fixed_count => 0, new_text => undef, error => undef, fixes_skipped => undef );

    my $doc = _parse( $src->text );
    if ( !$doc ) {
        $result{error} = PPI::Document->errstr;
        return \%result;
    }

    my ( $original, $lint_error ) = $self->_lint( $src, $doc );
    $result{violations} = $original;
    $result{error}      = $lint_error;
    my @fixable = grep { $self->_fixable_in_mode($_) } @$original;

    # PPI and Puff::Source disagree about lines when there is a CR, so
    # offsets would be wrong: lint only, and offer no fixes.
    if ( $src->has_cr ) {
        $result{fixes_skipped} = 'CR or CRLF line endings: fixes not applied'
            if $self->{fix_mode} ne 'none' && @fixable;
        $_->fixable(0) for @$original;
    }

    # Never fix on the strength of a partial lint.
    elsif ( $self->{fix_mode} ne 'none' && @fixable && !$lint_error ) {
        my ( $text, $final, $error ) = $self->_fix_loop( $src, $doc, $original );
        if ($error) {
            $result{error} = $error;
        }
        elsif ( $text ne $src->text ) {
            my $remaining = grep { $self->_fixable_in_mode($_) } @$final;
            $result{new_text}    = $text;
            $result{violations}  = $final;
            $result{fixed_count} = @fixable > $remaining ? @fixable - $remaining : 0;
        }
    }

    $_->file($file) for @{ $result{violations} };
    return \%result;
}

# Returns ($text, $violations, $error). $src and $doc are kept alive for each
# pass because PPI drops token locations when its document is destroyed.
sub _fix_loop ( $self, $src, $doc, $violations ) {
    for my $pass ( 1 .. $MAX_PASSES + 1 ) {
        my ( $fixes, $fix_error ) = $self->_collect_fixes( $src, $violations );
        return ( undef, undef, $fix_error ) if $fix_error;
        my ($text) = Puff::Edits::apply( $src->text, $fixes );
        return ( $src->text, $violations, undef ) if $text eq $src->text;
        return ( undef, undef, 'fix loop did not converge' ) if $pass > $MAX_PASSES;

        $src = Puff::Source->from_string($text);
        $doc = _parse($text) or return ( undef, undef, PPI::Document->errstr );
        ( $violations, my $lint_error ) = $self->_lint( $src, $doc );
        return ( undef, undef, $lint_error ) if $lint_error;
    }
    die 'unreachable';
}

# Returns (\@fixes, $error). A Puff::Fix::Decline exception is a decline;
# any other exception is an error and no fixes are applied.
sub _collect_fixes ( $self, $src, $violations ) {
    my @fixes;
    for my $v ( grep { $self->_fixable_in_mode($_) } @$violations ) {
        my $fix = Puff::Fix->new( source => $src );
        my $ok  = eval { $v->rule->fix( $v, $fix ) };
        if ( !defined $ok && $@ && !( blessed $@ && $@->isa('Puff::Fix::Decline') ) ) {
            return ( undef, sprintf( 'rule %s fix failed: %s', $v->code, "$@" =~ s/\s+\z//r ) );
        }
        my @edits = @{ $fix->edits };
        next unless $ok && @edits;
        push @fixes, {
            edits => \@edits,
            key   => [ min( map { $_->{start} } @edits ), $v->code, $v->line ],
            id    => $v,
        };
    }
    return ( \@fixes, undef );
}

sub _fixable_in_mode ( $self, $v ) {
    return 0 unless $v->fixable && $v->rule;

    # A rule with no fix never gets one, whatever its violations claim.
    return 0 if $v->rule->fix_safety eq 'none';
    my $safety = $v->fix_safety;
    my $mode   = $self->{fix_mode};
    return 1 if $safety eq 'safe'   && ( $mode eq 'safe' || $mode eq 'unsafe' );
    return 1 if $safety eq 'unsafe' && $mode eq 'unsafe';
    return 0;
}

sub _parse ($text) {
    my $doc = PPI::Document->new( \$text ) or return;
    $doc->index_locations;
    return $doc;
}

sub _lint ( $self, $src, $doc ) {
    my $suppressions = Puff::Suppressions->new($doc);
    my %found;    # class name => elements, shared between rules
    my ( @violations, @errors );
    for my $rule ( @{ $self->{rules} } ) {
        my $applies = $rule->applies_to;
        my %seen;
        my @elems = grep { !$seen{ refaddr($_) }++ }
            map { @{ $found{$_} //= $doc->find($_) || [] } } ref $applies ? @$applies : $applies;
        my @found;
        my $ok = eval {
            push @found, $rule->check( $_, $doc ) for @elems;
            die "check returned a non-violation\n" if grep { !( blessed $_ && $_->isa('Puff::Violation') ) } @found;
            1;
        };
        if ( !$ok ) {
            my $msg = ( $@ || 'unknown error' ) =~ s/\s+\z//r;
            push @errors, sprintf( 'rule %s failed: %s', $rule->code, $msg );
            next;
        }
        push @violations, grep { !$suppressions->is_suppressed( $_->code, $_->line ) } @found;
    }
    for my $problem ( @{ $suppressions->problems } ) {
        push @violations, Puff::Violation->new(
            rule    => undef,
            code    => 'P001',
            element => undef,
            line    => $problem->{line},
            column  => $problem->{column},
            message => $problem->{message},
            fixable => 0,
        );
    }
    my @sorted = sort { $a->line <=> $b->line || $a->column <=> $b->column || $a->code cmp $b->code } @violations;
    return ( \@sorted, @errors ? join( '; ', @errors ) : undef );
}

1;

# ABSTRACT: Lint and fix one file

__END__

=pod

=head1 SYNOPSIS

    my $engine = Puff::Engine->new( rules => \@rules, fix_mode => 'safe' );
    my $result = $engine->process_source( $source, file => $path );

=head1 DESCRIPTION

C<fix_mode> is C<none>, C<safe> (apply fixes of violations whose
C<fix_safety> is C<safe>) or C<unsafe> (C<safe> and C<unsafe> fixes). A
violation's C<fix_safety> is its rule's unless the rule set one for it.
A violation of a rule whose C<fix_safety> is C<none> is never fixed.

C<process_source> parses the text with PPI, runs each rule's C<check> on the
elements matching its C<applies_to>, drops suppressed violations and adds a
P001 violation for every suppression comment without codes. When fixing, it
applies fixes through L<Puff::Edits>, re-parses and re-lints, and repeats
while the text changes, for at most 10 passes. A C<fix> that returns false,
records no edits or dies with a L<Puff::Fix::Decline> (C<< Puff::Fix->decline >>)
is a decline; a C<fix> that dies with anything else is an error. It never
writes files. It returns a hashref:

=over

=item violations

Remaining L<Puff::Violation>s, sorted by line, column and code, with C<file>
set. When the text was fixed, these come from the fixed text.

C<element> on these violations is not valid after C<process_source>
returns: the PPI document it belonged to is gone (and P001 violations have
no element at all).

=item new_text

The fixed text, or undef if nothing changed or fixing failed.

=item fixed_count

The number of violations fixable in the current mode found in the original
text, minus the number of such violations left in the fixed text (never
below 0); 0 when C<new_text> is undef.

=item error

The PPI error when the text (or the fixed text) does not parse, or
C<fix loop did not converge> when the text still changes after 10 passes.
When a rule's C<check> dies or returns something that is not a
L<Puff::Violation>, C<rule CODE failed: MESSAGE> (several joined with
C<; >); that rule's violations for the file are dropped and the other rules
still report. When a rule's C<fix> dies with anything but a decline,
C<rule CODE fix failed: MESSAGE> and fixing is abandoned for the file. A rule failure in the original lint means no fixes are
attempted; one while re-linting fixed text abandons fixing. In every error
case the original text is kept and the violations are those of the
original lint.

=item fixes_skipped

Set when fixes were wanted but not applied because the text contains a
carriage return (CRLF or lone CR line endings). For such text every
violation has C<fixable> 0, in every mode.

=back

C<builtin_rules_info> lists the built-in P001 code and summary for
C<puff rules>.

=cut
