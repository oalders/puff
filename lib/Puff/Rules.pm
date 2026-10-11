package Puff::Rules;

use v5.36;

use Module::Pluggable::Object ();
use Path::Tiny                qw( path );
use Puff::Path                qw( display_lines display_name display_text );

my $CODE_RE  = qr/\A[A-Z]+[0-9]{3}\z/;
my $RESERVED = 'P001';

sub load ( $class, %args ) {
    my @candidates = _escape_warnings(
        sub {
            Module::Pluggable::Object->new(
                search_path      => ['Puff::Rule'],
                require          => 1,
                on_require_error => sub ( $module, $error ) {
                    die "Cannot load rule $module: " . display_lines("$error");
                },
            )->plugins;
        }
    );

    for my $dir ( @{ $args{rule_paths} // [] } ) {
        my $root = path($dir);
        die "rule-paths: '" . display_name($dir) . "' is not a directory\n" unless $root->is_dir;
        my @files = sort grep {/\.pm\z/} map { $_->stringify } _all_files($root);
        for my $file (@files) {
            my $abs = path($file)->absolute->stringify;
            my @packages;

            # Perl's errors and warnings are byte strings with the path inside, so show them
            # line by line (display_name would escape the newlines) like other path errors.
            my $loaded = _escape_warnings(
                sub {
                    eval {
                        my $text = path($file)->slurp_utf8;
                        @packages = $text =~ /^\s*package\s+([\w:]+)/mg;
                        require $abs;    # puff: ignore S016 - rule-paths come from the user's own config
                        1;
                    };
                }
            );
            unless ($loaded) {
                my $error = display_lines( "$@" || 'unknown error' );
                $error .= "\n" unless $error =~ /\n\z/;
                die "rule-paths: cannot load '" . display_name($abs) . "': $error";
            }
            push @candidates, @packages;
        }
    }

    my ( %seen, %by_code, @classes );
    for my $candidate (@candidates) {
        next if $seen{$candidate}++;
        next if $candidate eq 'Puff::Rule' || !$candidate->isa('Puff::Rule');
        my $code = $candidate->code;
        die "Rule "
            . display_name($candidate)
            . " has invalid code '"
            . ( defined $code ? display_name("$code") : 'undef' )
            . "' (expected letters followed by three digits)\n"
            unless defined $code && $code =~ $CODE_RE;
        my ( $shown, $shown_code ) = map { display_name("$_") } $candidate, $code;
        die "Rule $shown uses code $shown_code, which is reserved for the puff engine\n"
            if $code eq $RESERVED;
        die "Rule $shown uses code $shown_code, but the prefix ALL is reserved for selecting every rule\n"
            if index( $code, 'ALL' ) == 0;
        if ( my $other = $by_code{$code} ) {
            die 'Rules ' . display_name($other) . " and $shown both use code $shown_code\n";
        }
        $by_code{$code} = $candidate;
        push @classes, $candidate;
    }
    my @sorted = sort { $a->code cmp $b->code } @classes;
    return @sorted;
}

# Runs $code with any warning shown through display_lines, passed on to the
# previous __WARN__ handler if there is one. The text ends in a newline so
# perl does not add a second "at ... line N".
sub _escape_warnings ($code) {
    my $prev = $SIG{__WARN__};
    local $SIG{__WARN__} = sub ($warning) {
        my $text = display_lines("$warning");
        $text .= "\n" unless $text =~ /\n\z/;
        ref $prev eq 'CODE' ? $prev->($text) : warn $text;
    };
    return $code->();
}

sub _all_files ($dir) {
    my @found;
    for my $child ( $dir->children ) {
        push @found, $child->is_dir ? _all_files($child) : $child;
    }
    return @found;
}

sub instantiate ( $class, $classes, %args ) {
    my $all = sub (@list) {
        map { $_ eq 'ALL' ? '' : $_ } @list;
    };    # '' is a prefix of every code
    my @select  = $all->( @{ $args{select} // [] }, @{ $args{extend_select} // [] } );
    my @ignore  = $all->( @{ $args{ignore} // [] } );
    my $options = $args{rule_options} // {};

    my @codes = ( $RESERVED, map { $_->code } @$classes );
    for my $selector (@select) {
        die 'Unknown rule selector: ' . display_text($selector) . "\n"
            unless grep { index( $_, $selector ) == 0 } @codes;
    }

    my @rules;
    for my $rule_class ( sort { $a->code cmp $b->code } @$classes ) {
        my $code = $rule_class->code;
        next unless $rule_class->explicit_select ? _names( $code, \@select ) : _matches( $code, \@select );
        next if _matches( $code, \@ignore );

        my $given = $options->{$code} // {};
        my $known = $rule_class->options;
        for my $name ( sort keys %$given ) {
            die "Unknown option '" . display_text($name) . "' for rule $code\n" unless exists $known->{$name};
        }
        push @rules, $rule_class->new( options => $given );
    }
    return @rules;
}

sub _matches ( $code, $prefixes ) {
    return scalar grep { index( $code, $_ ) == 0 } @$prefixes;
}

# Whether a selector is the exact code or ALL (already mapped to '').
sub _names ( $code, $selectors ) {
    return scalar grep { $_ eq $code || $_ eq q{} } @$selectors;
}

1;

# ABSTRACT: Load rules and select the enabled ones

__END__

=pod

=head1 SYNOPSIS

    my @classes = Puff::Rules->load( rule_paths => ['xt/puff-rules'] );
    my @rules   = Puff::Rules->instantiate(
        \@classes,
        select       => ['S'],
        ignore       => ['S002'],
        rule_options => { S001 => { foo => 1 } },
    );

=head1 DESCRIPTION

C<load> finds every C<Puff::Rule::*> class on C<@INC> plus every C<.pm> file
under each rule-path directory (loaded by file path). Classes that are
L<Puff::Rule> subclasses count as rules. It dies if a code does not match
C</\A[A-Z]+[0-9]{3}\z/>, if two rules share a code (naming both packages), or
if a rule claims C<P001>, which is reserved for the engine, or a code starting
with C<ALL>, which is reserved for the selector that matches every rule. Classes are
returned sorted by code.

C<instantiate> enables the rules whose code starts with any C<select> or
C<extend_select> prefix and with no C<ignore> prefix, and returns objects
sorted by code. The selector C<ALL> matches every rule, in any of the three
lists. A rule whose C<explicit_select> is true (see L<Puff::Rule>) is
enabled only by its exact code or C<ALL>, never by a shorter prefix, so the
default C<select> of C<S> and C<B> leaves it off. It dies if a C<select> or C<extend_select> entry is not a
prefix of any loaded rule's code (or of C<P001>) (C<Unknown rule selector:
X>), or if C<rule_options> names an option a selected rule does not declare.
An C<ignore> entry that matches nothing is allowed.

C<load> also dies if a C<Puff::Rule::*> module on C<@INC> fails to compile.
Load errors, and warnings raised while rules load, have their file names
and control characters escaped as L<Puff::Path> C<display_lines> does.
Warnings go to any C<__WARN__> handler already in place.

=cut
