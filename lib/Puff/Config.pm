package Puff::Config;

use v5.36;

use Encode     ();
use Path::Tiny qw( path );
use Puff::Path qw( display_name );
use TOML::Tiny qw( from_toml );

my @DEFAULT_EXCLUDE = qw( /local /blib /.build /.git );
my %KNOWN_KEY       = map { $_ => 1 } qw( select extend-select ignore rule-paths exclude unsafe-fixes rules );

sub load ( $class, %args ) {
    my $cli  = $args{cli} // {};
    my %self = (
        select        => [qw( S B )],
        extend_select => [],
        ignore        => [],
        rule_paths    => [],
        exclude       => [@DEFAULT_EXCLUDE],
        unsafe_fixes  => 0,
        rule_options  => {},
    );

    my $file;
    if ( !$args{no_config} ) {
        if ( defined $args{path} ) {
            $file = path( $args{path} );
            die "Config file '" . display_name("$file") . "' not found\n" unless $file->is_file;
        }
        else {
            my $default = path('.puff.toml');
            $file = $default if $default->is_file;
        }
    }
    $class->_read_file( \%self, $file ) if $file;
    $self{root} = ( $file ? $file->absolute->parent : path('.') )->realpath->stringify;

    $self{select} = [ @{ $cli->{select} } ] if defined $cli->{select};
    push @{ $self{extend_select} }, @{ $cli->{extend_select} // [] };
    push @{ $self{ignore} }, @{ $cli->{ignore} // [] };
    $self{unsafe_fixes} = $cli->{unsafe_fixes} ? 1 : 0 if defined $cli->{unsafe_fixes};

    return bless \%self, $class;
}

sub _read_file ( $class, $self, $file ) {
    my $name = display_name("$file");
    my $text = eval { $file->slurp_utf8 };

    # A read error holds the raw path bytes; a TOML error is about the text.
    die "Invalid config file '$name': " . display_name( "$@" =~ s/ at \S+ line \d+\.?\s*\z|\s+\z//r ) . "\n"
        unless defined $text;
    my $data = eval { from_toml($text) };
    die "Invalid config file '$name': $@\n" if !$data || $@;
    ref $data eq 'HASH' or die "Invalid config file '$name'\n";

    for my $key ( sort keys %$data ) {
        die "Unknown key '$key' in config file '$name'\n" unless $KNOWN_KEY{$key};
    }

    my $list = sub ($key) {
        my $value = $data->{$key};
        die "Key '$key' in config file '$name' must be an array of strings\n"
            if ref $value ne 'ARRAY' || grep { ref $_ || !defined } @$value;
        return [@$value];
    };

    # An empty string is a prefix of every code, so it would quietly mean
    # ALL.
    my $selectors = sub ($key) {
        my $value = $list->($key);
        die "Key '$key' in config file '$name' has an empty rule selector\n" if grep { !/\S/ } @$value;
        return $value;
    };
    $self->{select}        = $selectors->('select') if exists $data->{select};
    $self->{extend_select} = $selectors->('extend-select') if exists $data->{'extend-select'};
    $self->{ignore}        = $selectors->('ignore') if exists $data->{ignore};

    # TOML gives characters; paths are bytes, like the config file's own
    # path and the paths is_excluded is given.
    push @{ $self->{exclude} }, map { Encode::encode_utf8($_) } @{ $list->('exclude') } if exists $data->{exclude};
    if ( exists $data->{'rule-paths'} ) {
        my $base = $file->absolute->parent;
        $self->{rule_paths} = [
            map { path($_)->is_absolute ? $_ : $base->child($_)->stringify }
            map { Encode::encode_utf8($_) } @{ $list->('rule-paths') }
        ];
    }

    if ( exists $data->{'unsafe-fixes'} ) {
        my $value = $data->{'unsafe-fixes'};
        die "unsafe-fixes must be true or false in config file '$name'\n"
            unless ref $value && ref $value eq 'JSON::PP::Boolean';
        $self->{unsafe_fixes} = $value ? 1 : 0;
    }

    if ( exists $data->{rules} ) {
        my $rules = $data->{rules};
        die "Key 'rules' in config file '$name' must be a table\n" if ref $rules ne 'HASH';
        for my $code ( keys %$rules ) {
            die "Key 'rules.$code' in config file '$name' must be a table\n" if ref $rules->{$code} ne 'HASH';
            $self->{rule_options}{$code} = { %{ $rules->{$code} } };
        }
    }
    return;
}

sub select        ($self) { return $self->{select} }
sub extend_select ($self) { return $self->{extend_select} }
sub ignore        ($self) { return $self->{ignore} }
sub rule_paths    ($self) { return $self->{rule_paths} }
sub exclude       ($self) { return $self->{exclude} }
sub unsafe_fixes  ($self) { return $self->{unsafe_fixes} }
sub rule_options  ($self) { return $self->{rule_options} }
sub root          ($self) { return $self->{root} }

# $relpath is relative to the directory being searched; $base is that
# directory relative to the root ('' for the root itself, undef when it is
# outside the root, which anchors /entries to the searched directory).
sub is_excluded ( $self, $relpath, $base = '' ) {
    my @segments  = _segments($relpath);
    my @base      = _segments( $base // '' );
    my @from_root = ( @base, @segments );
    for my $entry ( @{ $self->{exclude} } ) {
        if ( $entry =~ m{\A/} ) {
            my @entry = _segments($entry);
            next if _has_prefix( \@entry, \@base );    # the user asked for this directory
            return 1 if _has_prefix( \@entry, \@from_root );
        }
        elsif ( $entry !~ m{/} ) {
            return 1 if grep { $_ eq $entry } @segments;
        }
        else {
            return 1 if _has_prefix( [ _segments($entry) ], \@segments );
        }
    }
    return 0;
}

sub _segments ($path) {
    return grep { length && $_ ne '.' } split m{/}, $path;
}

sub _has_prefix ( $prefix, $segments ) {
    return 0 if !@$prefix || @$prefix > @$segments;
    return !grep { $prefix->[$_] ne $segments->[$_] } 0 .. $#$prefix;
}

1;

# ABSTRACT: Read .puff.toml and merge command-line flags

__END__

=pod

=head1 SYNOPSIS

    my $config = Puff::Config->load(
        path      => undef,
        no_config => 0,
        cli       => { select => ['S'], ignore => ['S002'], unsafe_fixes => 1 },
    );
    say for @{ $config->select };
    say 'skip' if $config->is_excluded('local/lib/X.pm');    # relative to root
    say 'skip' if $config->is_excluded( 'lib/X.pm', 'local' );    # searching local/

=head1 DESCRIPTION

With C<path> undefined, reads C<./.puff.toml> if it exists; an explicit
C<path> that does not exist is an error. C<no_config> ignores files entirely.
Unknown top-level keys, and malformed values, die with a message naming the
key and file.

Defaults: C<select> C<["S", "B"]>, C<extend-select> and C<ignore> empty,
C<exclude> C</local /blib /.build /.git>, C<unsafe-fixes> false. Entries in the
file's C<exclude> are added to the default list (the defaults always apply).
Relative C<rule-paths> are resolved against the config file's directory;
absolute ones are used as they are. C<unsafe-fixes> must be a TOML boolean.
C<[rules.CODE]> tables become C<rule_options>.

=head2 Merging command-line values

Defined C<cli> values override the file. A C<select> list I<replaces> the
configured one; C<extend_select> and C<ignore> lists are I<appended> to the
configured ones; C<unsafe_fixes> overrides.

=head2 root

The project root: the directory holding the config file that was read, or
the current directory when none was. Resolved with C<realpath>.

=head2 is_excluded($relpath, $base = '')

C<$relpath> is a path relative to the directory being searched, and
C<$base> is that directory relative to L</root> (C<''> for the root itself,
C<undef> when the directory is outside the root). Entries match by
segments, never mid-name:

=over

=item C</local>

A leading C</> anchors the entry to the root: it matches C<$base/$relpath>
when that starts with the entry's segments. So C</local> excludes
C<./local/lib/X.pm> but not C<t/local/http.t>. The defaults are anchored
this way. When the directory being searched is outside the root (C<$base>
undef), anchored entries are anchored to that directory instead, so
C<puff check /elsewhere/proj> still skips C<proj/local>. An anchored entry
that covers the searched directory itself is ignored: C<puff check local>
checks everything under C<local>.

=item C<vendor>

An entry without C</> matches any segment of C<$relpath> with that name, at
any depth.

=item C<t/corpus>

Any other entry matches a prefix of C<$relpath> at a segment boundary, so it
matches C<t/corpus/x.pl> but not C<xt/corpus/x.pl>.

=back

=cut
