package Puff::Runner;

use v5.36;

use Path::Tiny   qw( path );
use Puff::Source ();
use Text::Diff   qw( diff );

my $PERL_FILE     = qr/\.(?:pl|pm|t|psgi)\z/;
my $SHEBANG_BYTES = 256;

sub new ( $class, %args ) {
    return bless {
        config   => $args{config},
        engine   => $args{engine},
        mode     => $args{mode} // 'lint',    # lint, fix or diff
        progress => $args{progress},          # called as ($done, $total) after each file
    }, $class;
}

# The files a run of @paths would check, in order: a path string for each,
# or { file, error } for a path that does not exist.
sub files ( $self, @paths ) {
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
    return @files;
}

sub run ( $self, @paths ) {
    my @files    = $self->files(@paths);
    my $progress = $self->{progress};
    my @results;
    $progress->( 0, scalar @files ) if $progress;
    for my $file (@files) {
        push @results, ref $file ? $file : $self->_process($file);
        $progress->( scalar @results, scalar @files ) if $progress;
    }
    return { files => \@results, exit_code => $self->exit_code( \@results ) };
}

sub exit_code ( $self, $results ) {
    return 2 if grep { defined $_->{error} } @$results;
    return 1 if grep { @{ $_->{violations} // [] } } @$results;
    return 1 if $self->{mode} eq 'diff' && grep { defined $_->{diff} } @$results;
    return 0;
}

sub _find ( $self, $root ) {
    my $config  = $self->{config};
    my $project = path( $config->root );
    my $real    = $root->realpath;
    my $base    = $project->subsumes($real) ? $real->relative($project)->stringify : undef;

    my @found;
    my @queue = $root;
    while ( my $dir = shift @queue ) {
        for my $child ( sort { $a->basename cmp $b->basename } $dir->children ) {
            next if $config->is_excluded( $child->relative($root)->stringify, $base );
            if ( $child->is_dir ) {
                push @queue, $child unless -l $child;
            }
            elsif ( $child->basename =~ $PERL_FILE ) {
                push @found, $child->stringify;
            }
            elsif ( $child->basename !~ /\./ && _has_perl_shebang($child) ) {
                push @found, $child->stringify;
            }
        }
    }
    return @found;
}

# True when the first line (within the first $SHEBANG_BYTES bytes) is
# "#!/path/perl...", or "#!/usr/bin/env perl" with any env options before
# perl. Unreadable files and files with a NUL byte (binaries) are false.
sub _has_perl_shebang ($file) {
    return 0 unless -f $file;    # never open a FIFO or device: it could block
    open my $fh, '<:raw', $file or return 0;
    defined read( $fh, my $head, $SHEBANG_BYTES ) or return 0;
    close $fh;
    return 0 if $head =~ /\0/;
    my ($line) = $head =~ /\A#!([^\n]*)/ or return 0;
    my ( $interpreter, @args ) = split ' ', $line;
    return 0 unless defined $interpreter;
    my $name = $interpreter =~ s{\A.*/}{}r;
    if ( $name eq 'env' ) {
        shift @args while @args && ( $args[0] =~ /\A-/ || $args[0] =~ /=/ );
        return 0 unless @args;
        $name = $args[0] =~ s{\A.*/}{}r;
    }
    return $name =~ /\Aperl/ ? 1 : 0;
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
recursively for C<*.pl>, C<*.pm>, C<*.t> and C<*.psgi> files, and for files
with no C<.> in their name whose first line is a Perl shebang: C<#!>
followed by a path whose basename starts with C<perl> (C</usr/bin/perl -w>,
C</opt/perl/bin/perl5.36.0>), or C<env> followed by C<perl>
(C<#!/usr/bin/env perl>, C<#!/usr/bin/env -S perl -w>). Only the first 256
bytes are read; unreadable files and files containing a NUL byte are
skipped silently. Directory searches skip
anything the config's C<exclude> matches (see
L<Puff::Config/is_excluded>: entries starting with C</>, including the
defaults, are anchored to the project root, others are matched relative to
the directory being searched); symlinked directories are not followed. A file named explicitly
is always checked, whatever its name. A file reached twice (named twice,
by different spellings of its path, or named and also found in a directory)
is checked once.

C<mode> is C<lint> (report only), C<fix> (write fixed files, only when the
text changed) or C<diff> (compute a unified diff, write nothing). The
engine's C<fix_mode> decides which fixes are worked out.

C<files> takes the same paths and returns the files C<run> would check, in
order: a path string for each, or C<< { file => $path, error => $message } >>
for a path that does not exist. A C<progress> code ref passed to C<new> is
called as C<< $progress->($done, $total) >> once the files are found and again after each one is checked.

C<run> returns C<< { files => [...], exit_code => N } >>. Each file entry
has C<file>, C<violations> (remaining), C<fixed_count>, and when relevant
C<error> (read, parse, rule, engine, fix or write failure; the file is
left unchanged, and other files are still processed), C<fixes_skipped>, C<diff> (diff mode) and C<written> (fix mode).

The exit code is 2 if any file has an error, else 1 if violations remain or
diff mode would change something, else 0.

=cut
