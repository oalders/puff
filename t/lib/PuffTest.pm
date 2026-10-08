package PuffTest;

use v5.36;

use Exporter     qw( import );
use Path::Tiny   qw( path );
use Puff::Engine ();
use Puff::Rules  ();
use Puff::Source ();
use Test2::V0;

our @EXPORT_OK = qw( run_corpus );
our @EXPORT    = @EXPORT_OK;

sub run_corpus ($code) {
    my ($class) = grep { $_->code eq $code } Puff::Rules->load;
    die "No rule with code $code\n" unless $class;
    my $rule = $class->new;

    my $dir = path( 't', 'corpus', $code );
    my @files = sort grep { /\.pl\z/ && !/\.fixed\.pl\z/ } map { $_->stringify } $dir->children;
    die "No corpus files in $dir\n" unless @files;

    for my $file (@files) {
        subtest $file => sub { _check_file( $rule, $code, $file ) };
    }
    return;
}

sub _check_file ( $rule, $code, $file ) {
    my $src = Puff::Source->from_file($file);

    my $lint = _engine( $rule, 'none' )->process_source( $src, file => $file );
    is( $lint->{error}, undef, 'lint has no error' );
    is( _lines( $lint->{violations}, $code ), _expected_lines( $src->text, $code ),
        'reported lines match # expect comments' );

    my $fixed = _engine( $rule, 'unsafe' )->process_source( $src, file => $file );
    is( $fixed->{error}, undef, 'fix has no error' );
    my $fixed_file = $file =~ s/\.pl\z/.fixed.pl/r;
    my $new_text   = $fixed->{new_text} // $src->text;
    if ( -e $fixed_file ) {
        is( $new_text, Puff::Source->from_file($fixed_file)->text, "fixed text matches $fixed_file" );
    }
    else {
        is( $new_text, $src->text, 'fixer leaves the file unchanged' );
    }

    my $relint = _engine( $rule, 'none' )->process_source( Puff::Source->from_string($new_text), file => $file );
    is( $relint->{error}, undef, 're-lint of fixed text has no error' );
    my @left = grep { $_->code eq $code && $_->fixable } @{ $relint->{violations} };
    is( [ map { $_->line } @left ], [], "no fixable $code violations left after fixing" );
    return;
}

sub _engine ( $rule, $mode ) {
    return Puff::Engine->new( rules => [$rule], fix_mode => $mode );
}

sub _lines ( $violations, $code ) {
    return [ map { $_->line } grep { $_->code eq $code } @$violations ];
}

# A line with "# expect: S001" (codes separated by spaces or commas; repeat a
# code for each violation expected on that line).
sub _expected_lines ( $text, $code ) {
    my @lines;
    my $n = 0;
    for my $line ( split /\n/, $text ) {
        $n++;
        next unless $line =~ /#\s*expect:\s*([A-Z0-9,\s]+)/;
        push @lines, ($n) x grep { $_ eq $code } split /[\s,]+/, $1;
    }
    return \@lines;
}

1;

# ABSTRACT: Corpus test harness for puff rules

__END__

=pod

=head1 SYNOPSIS

    use lib 't/lib';
    use PuffTest qw( run_corpus );
    run_corpus('S001');
    done_testing;

=head1 DESCRIPTION

C<run_corpus($code)> runs one subtest per C<t/corpus/$code/*.pl> file
(skipping C<*.fixed.pl>), using only the rule with that code:

=over

=item 1.

Lint the file. The lines reported for C<$code> must equal the lines carrying
an C<# expect: CODE> comment. Repeat the code (C<# expect: S001 S001>) when a
line has more than one violation.

=item 2.

Fix it with unsafe fixes. If C<NAME.fixed.pl> exists the fixed text must
equal it exactly; otherwise the text must be unchanged.

=item 3.

Lint the fixed text again. Every remaining C<$code> violation must have
C<fixable> 0. The C<# expect:> comments in the fixed text are not checked.

=back

Linting must not return an error at any step. Run tests from the
distribution root, since corpus paths are relative to it.

=cut
