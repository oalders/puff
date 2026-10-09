package Puff::Reporter::Text;

use v5.36;

use IO::Handle ();

sub new ( $class, %args ) {
    return bless {
        fix_mode   => $args{fix_mode} // 'safe',    # the fixes --fix would apply
        mode       => $args{mode}     // 'lint',
        statistics => $args{statistics},            # one line per rule instead of per violation
    }, $class;
}

# One line per rule code, most violations first: the count, the code, the
# fix marker when any of them can be fixed, and the rule's summary, with
# "(N fixable)" when only some can.
sub _statistics ( $self, $by_code, $out ) {
    my @codes = sort { $by_code->{$b}{count} <=> $by_code->{$a}{count} || $a cmp $b } keys %$by_code;
    my $width = length( $codes[0] ? $by_code->{ $codes[0] }{count} : 0 );
    for my $code (@codes) {
        my $stat    = $by_code->{$code};
        my $summary = $stat->{rule} ? $stat->{rule}->summary : q{};
        my $partial = $stat->{fixable} && $stat->{fixable} < $stat->{count} ? " ($stat->{fixable} fixable)" : q{};
        my $line    = sprintf "%*d  %-5s %-5s %s%s", $width, $stat->{count}, $code, $stat->{marker} =~ s/\A //r, $summary, $partial;
        print {$out} $line =~ s/\s+\z//r, "\n";
    }
    return;
}

sub report ( $self, $run, $out, $err ) {
    my @files = sort { $a->{file} cmp $b->{file} } @{ $run->{files} };

    $self->report_errors( \@files, $err );

    if ( $self->{mode} eq 'diff' ) {
        my @changed = grep { defined $_->{diff} } @files;
        print {$out} $_->{diff} for @changed;
        my $count = 0;
        $count += $_->{fixed_count} for @changed;
        printf {$err} "Would fix %s in %s.\n", _n( $count, 'violation' ), _n( scalar @changed, 'file' );
        $self->flush_or_die($out);
        return;
    }

    my ( $total, $enabled, $unsafe ) = ( 0, 0, 0 );
    my %by_code;
    for my $file (@files) {
        for my $v ( @{ $file->{violations} } ) {
            my $marker = $self->_marker($v);
            $total++;
            $enabled++ if $marker eq ' [*]';
            $unsafe++  if $marker eq ' [**]';
            if ( $self->{statistics} ) {
                my $stat = $by_code{ $v->code } //= { count => 0, fixable => 0, marker => q{}, rule => $v->rule };
                $stat->{count}++;
                next unless $marker;
                $stat->{fixable}++;
                $stat->{marker} = $marker;
                next;
            }
            printf {$out} "%s:%d:%d: %s %s%s\n", $v->file, $v->line, $v->column, $v->code, $v->message, $marker;
        }
    }
    $self->_statistics( \%by_code, $out ) if $self->{statistics};

    my $checked = grep { !defined $_->{error} } @files;
    printf {$out} "Found %s (checked %s).\n", _n( $total, 'violation' ), _n( $checked, 'file' );
    print {$out} "$enabled fixable with --fix\n"               if $enabled;
    print {$out} "$unsafe more fixable with --unsafe-fixes\n" if $unsafe;
    if ( $self->{mode} eq 'fix' ) {
        my @written = grep { $_->{written} } @files;
        my $count   = 0;
        $count += $_->{fixed_count} for @written;
        printf {$out} "Fixed %s in %s.\n", _n( $count, 'violation' ), _n( scalar @written, 'file' );
    }
    $self->flush_or_die($out);
    return;
}

sub report_errors ( $class, $files, $err ) {
    for my $file (@$files) {
        print {$err} "$file->{file}: error: $file->{error}\n"   if defined $file->{error};
        print {$err} "$file->{file}: $file->{fixes_skipped}\n" if defined $file->{fixes_skipped};
    }
    return;
}

# Flushes $out and dies if writing to it failed (a full disk, a closed
# handle), so lost output is never silent. Shared with the other reporters.
sub flush_or_die ( $class, $out ) {
    $out->flush && !$out->error or die "puff: cannot write output: $!\n";
    return;
}

sub _marker ( $self, $v ) {
    return '' unless $v->fixable && $v->rule;
    my $safety = $v->rule->fix_safety;
    return ' [*]'  if $safety eq 'safe';
    return ''      if $safety ne 'unsafe';
    return $self->{fix_mode} eq 'unsafe' ? ' [*]' : ' [**]';
}

sub _n ( $count, $noun ) {
    return "$count $noun" . ( $count == 1 ? '' : 's' );
}

1;

# ABSTRACT: Report results as text, one line per violation

__END__

=pod

=head1 SYNOPSIS

    Puff::Reporter::Text->new( fix_mode => 'safe', mode => 'lint' )
        ->report( $run, \*STDOUT, \*STDERR );

=head1 DESCRIPTION

Takes the hashref returned by L<Puff::Runner/run>. Prints one line per
remaining violation, sorted by file, line and column:

    lib/Foo.pm:12:5: S002 Use three-argument open [*]

C<[*]> marks a violation that C<--fix> would fix with the current settings
(C<fix_mode> is C<safe> or C<unsafe>: the fixes C<--fix> applies); C<[**]>
marks one with an unsafe fix that is not enabled. Then C<Found N
violations (checked F files).>, where F counts the files read without an
error, C<M fixable with --fix> and C<K more fixable with
--unsafe-fixes> when those are non-zero, and in C<fix> mode C<Fixed N
violations in M files.>

With C<< statistics => 1 >> it prints one line per rule code instead of one
per violation, most violations first: the count, the code, the fix marker
when any can be fixed, the rule's summary, and C<(N fixable)> when only
some can. The summary lines follow as usual.

In C<diff> mode it prints each file's unified diff instead, and C<Would fix
N violations in M files.> on the error handle.

File errors and skipped fixes go to the error handle;
C<< Puff::Reporter::Text->report_errors(\@files, $err) >> prints them and is
shared with L<Puff::Reporter::JSON>. So is
C<< Puff::Reporter::Text->flush_or_die($out) >>, which flushes the output
handle and dies if any write to it failed.

=cut
