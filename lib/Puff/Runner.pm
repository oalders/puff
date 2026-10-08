package Puff::Runner;

use v5.36;

use Path::Tiny   qw( path );
use Puff::Source ();
use Text::Diff   qw( diff );

my $PERL_FILE = qr/\.(?:pl|pm|t|psgi)\z/;

sub new ( $class, %args ) {
    return bless {
        config => $args{config},
        engine => $args{engine},
        mode   => $args{mode} // 'lint',    # lint, fix or diff
    }, $class;
}

sub run ( $self, @paths ) {
    @paths = ('.') unless @paths;
    my ( @files, %seen );
    my $first = sub ($file) { !$seen{ path($file)->realpath }++ };    # a.pl and $PWD/a.pl are one file
    for my $given (@paths) {
        my $p = path($given);
        if ( $p->is_dir ) {
            push @files, grep { $first->($_) } $self->_find($p);
        }
        elsif ( -e $p ) {
            push @files, $p->stringify if $first->($p);
        }
        else {
            push @files, { file => $p->stringify, error => 'No such file or directory' };
        }
    }

    my @results = map { ref $_ ? $_ : $self->_process($_) } @files;
    return { files => \@results, exit_code => $self->exit_code( \@results ) };
}

sub exit_code ( $self, $results ) {
    return 2 if grep { defined $_->{error} } @$results;
    return 1 if grep { @{ $_->{violations} // [] } } @$results;
    return 1 if $self->{mode} eq 'diff' && grep { defined $_->{diff} } @$results;
    return 0;
}

sub _find ( $self, $root ) {
    my @found;
    my @queue = $root;
    while ( my $dir = shift @queue ) {
        for my $child ( sort { $a->basename cmp $b->basename } $dir->children ) {
            next if $self->{config}->is_excluded( $child->relative($root)->stringify );
            if ( $child->is_dir ) {
                push @queue, $child unless -l $child;
            }
            elsif ( $child->basename =~ $PERL_FILE ) {
                push @found, $child->stringify;
            }
        }
    }
    return @found;
}

sub _process ( $self, $file ) {
    my %out = ( file => $file, violations => [], fixed_count => 0 );

    my $src = eval { Puff::Source->from_file($file) };
    if ( !$src ) {
        $out{error} = ( $@ || 'cannot read file' ) =~ s/\s+\z//r;
        return \%out;
    }

    my $result = eval { $self->{engine}->process_source( $src, file => $file ) };
    if ( !$result ) {
        $out{error} = ( $@ || 'engine failed' ) =~ s/\s+\z//r;
        return \%out;
    }
    $out{violations}    = $result->{violations};
    $out{error}         = defined $result->{error} ? $result->{error} =~ s/\s+\z//r : undef;
    $out{fixes_skipped} = $result->{fixes_skipped};

    my $new = $result->{new_text};
    return \%out unless defined $new && $new ne $src->text;
    $out{fixed_count} = $result->{fixed_count};

    if ( $self->{mode} eq 'diff' ) {
        my $relative = $file =~ s{\A/+}{}r;
        $out{diff} = diff(
            \$src->text, \$new,
            { STYLE => 'Unified', FILENAME_A => "a/$relative", FILENAME_B => "b/$relative" }
        );
    }
    elsif ( $self->{mode} eq 'fix' ) {
        if ( eval { $src->write_file( $file, $new ); 1 } ) {
            $out{written} = 1;
        }
        else {
            $out{error}       = ( $@ || 'cannot write file' ) =~ s/\s+\z//r;
            $out{fixed_count} = 0;
        }
    }
    return \%out;
}

1;

# ABSTRACT: Find files, run the engine on each and work out the exit code

__END__

=pod

=head1 SYNOPSIS

    my $runner = Puff::Runner->new(
        config => $config,
        engine => Puff::Engine->new( rules => \@rules, fix_mode => 'unsafe' ),
        mode   => 'fix',
    );
    my $run = $runner->run(@paths);
    exit $run->{exit_code};

=head1 DESCRIPTION

C<run> checks the given paths (default C<.>). Directories are searched
recursively for C<*.pl>, C<*.pm>, C<*.t> and C<*.psgi> files, skipping
anything the config's C<exclude> matches, relative to the directory being
searched; symlinked directories are not followed. A file named explicitly
is always checked, whatever its name. A file reached twice (named twice,
by different spellings of its path, or named and also found in a directory)
is checked once.

C<mode> is C<lint> (report only), C<fix> (write fixed files, only when the
text changed) or C<diff> (compute a unified diff, write nothing). The
engine's C<fix_mode> decides which fixes are worked out.

C<run> returns C<< { files => [...], exit_code => N } >>. Each file entry
has C<file>, C<violations> (remaining), C<fixed_count>, and when relevant
C<error> (read, parse, rule, engine, fix or write failure; the file is
left unchanged, and other files are still processed), C<fixes_skipped>, C<diff> (diff mode) and C<written> (fix mode).

The exit code is 2 if any file has an error, else 1 if violations remain or
diff mode would change something, else 0.

=cut
