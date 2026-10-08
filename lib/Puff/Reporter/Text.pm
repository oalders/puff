package Puff::Reporter::Text;

use v5.36;

sub new ( $class, %args ) {
    return bless {
        fix_mode => $args{fix_mode} // 'safe',    # the fixes --fix would apply
        mode     => $args{mode}     // 'lint',
    }, $class;
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
        return;
    }

    my ( $total, $enabled, $unsafe ) = ( 0, 0, 0 );
    for my $file (@files) {
        for my $v ( @{ $file->{violations} } ) {
            my $marker = $self->_marker($v);
            $total++;
            $enabled++ if $marker eq ' [*]';
            $unsafe++  if $marker eq ' [**]';
            printf {$out} "%s:%d:%d: %s %s%s\n", $v->file, $v->line, $v->column, $v->code, $v->message, $marker;
        }
    }

    printf {$out} "Found %s.\n", _n( $total, 'violation' );
    print {$out} "$enabled fixable with --fix\n"               if $enabled;
    print {$out} "$unsafe more fixable with --unsafe-fixes\n" if $unsafe;
    if ( $self->{mode} eq 'fix' ) {
        my @written = grep { $_->{written} } @files;
        my $count   = 0;
        $count += $_->{fixed_count} for @written;
        printf {$out} "Fixed %s in %s.\n", _n( $count, 'violation' ), _n( scalar @written, 'file' );
    }
    return;
}

sub report_errors ( $class, $files, $err ) {
    for my $file (@$files) {
        print {$err} "$file->{file}: error: $file->{error}\n"   if defined $file->{error};
        print {$err} "$file->{file}: $file->{fixes_skipped}\n" if defined $file->{fixes_skipped};
    }
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
violations.>, C<M fixable with --fix> and C<K more fixable with
--unsafe-fixes> when those are non-zero, and in C<fix> mode C<Fixed N
violations in M files.>

In C<diff> mode it prints each file's unified diff instead, and C<Would fix
N violations in M files.> on the error handle.

File errors and skipped fixes go to the error handle;
C<< Puff::Reporter::Text->report_errors(\@files, $err) >> prints them and is
shared with L<Puff::Reporter::JSON>.

=cut
