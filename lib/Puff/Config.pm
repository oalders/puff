package Puff::Config;

use v5.36;

use Path::Tiny qw( path );
use TOML::Tiny qw( from_toml );

my @DEFAULT_EXCLUDE = qw( local blib .build .git );
my %KNOWN_KEY       = map { $_ => 1 } qw( select extend-select ignore rule-paths exclude unsafe-fixes rules );

sub load ( $class, %args ) {
    my $cli = $args{cli} // {};
    my %self = (
        select        => ['S'],
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
            die "Config file '$file' not found\n" unless $file->is_file;
        }
        else {
            my $default = path('.puff.toml');
            $file = $default if $default->is_file;
        }
    }
    $class->_read_file( \%self, $file ) if $file;

    $self{select} = [ @{ $cli->{select} } ] if defined $cli->{select};
    push @{ $self{extend_select} }, @{ $cli->{extend_select} // [] };
    push @{ $self{ignore} },        @{ $cli->{ignore}        // [] };
    $self{unsafe_fixes} = $cli->{unsafe_fixes} ? 1 : 0 if defined $cli->{unsafe_fixes};

    return bless \%self, $class;
}

sub _read_file ( $class, $self, $file ) {
    my $data = eval { from_toml( $file->slurp_utf8 ) };
    die "Invalid config file '$file': $@\n" if !$data || $@;
    ref $data eq 'HASH' or die "Invalid config file '$file'\n";

    for my $key ( sort keys %$data ) {
        die "Unknown key '$key' in config file '$file'\n" unless $KNOWN_KEY{$key};
    }

    my $list = sub ($key) {
        my $value = $data->{$key};
        die "Key '$key' in config file '$file' must be an array of strings\n"
            if ref $value ne 'ARRAY' || grep { ref $_ || !defined } @$value;
        return [@$value];
    };

    $self->{select}        = $list->('select')        if exists $data->{select};
    $self->{extend_select} = $list->('extend-select') if exists $data->{'extend-select'};
    $self->{ignore}        = $list->('ignore')        if exists $data->{ignore};
    push @{ $self->{exclude} }, @{ $list->('exclude') } if exists $data->{exclude};

    if ( exists $data->{'rule-paths'} ) {
        my $base = $file->absolute->parent;
        $self->{rule_paths} = [ map { $base->child($_)->stringify } @{ $list->('rule-paths') } ];
    }

    $self->{unsafe_fixes} = $data->{'unsafe-fixes'} ? 1 : 0 if exists $data->{'unsafe-fixes'};

    if ( exists $data->{rules} ) {
        my $rules = $data->{rules};
        die "Key 'rules' in config file '$file' must be a table\n" if ref $rules ne 'HASH';
        for my $code ( keys %$rules ) {
            die "Key 'rules.$code' in config file '$file' must be a table\n" if ref $rules->{$code} ne 'HASH';
            $self->{rule_options}{$code} = { %{ $rules->{$code} } };
        }
    }
    return;
}

sub select ($self)        { return $self->{select} }
sub extend_select ($self) { return $self->{extend_select} }
sub ignore ($self)        { return $self->{ignore} }
sub rule_paths ($self)    { return $self->{rule_paths} }
sub exclude ($self)       { return $self->{exclude} }
sub unsafe_fixes ($self)  { return $self->{unsafe_fixes} }
sub rule_options ($self)  { return $self->{rule_options} }

sub is_excluded ( $self, $relpath ) {
    my @segments = grep { length && $_ ne '.' } split m{/}, $relpath;
    for my $entry ( @{ $self->{exclude} } ) {
        if ( $entry !~ m{/} ) {
            return 1 if grep { $_ eq $entry } @segments;
            next;
        }
        my @prefix = grep { length && $_ ne '.' } split m{/}, $entry;
        next if !@prefix || @prefix > @segments;
        return 1 unless grep { $prefix[$_] ne $segments[$_] } 0 .. $#prefix;
    }
    return 0;
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
    say 'skip' if $config->is_excluded('local/lib/X.pm');

=head1 DESCRIPTION

With C<path> undefined, reads C<./.puff.toml> if it exists; an explicit
C<path> that does not exist is an error. C<no_config> ignores files entirely.
Unknown top-level keys, and malformed values, die with a message naming the
key and file.

Defaults: C<select> C<["S"]>, C<extend-select> and C<ignore> empty,
C<exclude> C<local blib .build .git>, C<unsafe-fixes> false. Entries in the
file's C<exclude> are added to the default list (the defaults always apply).
C<rule-paths> are resolved relative to the config file's directory.
C<[rules.CODE]> tables become C<rule_options>.

=head2 Merging command-line values

Defined C<cli> values override the file. A C<select> list I<replaces> the
configured one; C<extend_select> and C<ignore> lists are I<appended> to the
configured ones; C<unsafe_fixes> overrides.

=head2 is_excluded($relpath)

An entry without C</> matches any path segment of that name. An entry with
C</> matches a path prefix at a segment boundary, so C<t/corpus> matches
C<t/corpus/x.pl> but not C<xt/corpus/x.pl>.

=cut
