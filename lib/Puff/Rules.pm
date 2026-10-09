package Puff::Rules;

use v5.36;

use Module::Pluggable::Object ();
use Path::Tiny                qw( path );

my $CODE_RE  = qr/\A[A-Z]+[0-9]{3}\z/;
my $RESERVED = 'P001';

sub load ( $class, %args ) {
    my @candidates = Module::Pluggable::Object->new(
        search_path      => ['Puff::Rule'],
        require          => 1,
        on_require_error => sub ( $module, $error ) {
            die "Cannot load rule $module: $error";
        },
    )->plugins;

    for my $dir ( @{ $args{rule_paths} // [] } ) {
        my $root = path($dir);
        die "rule-paths: '$dir' is not a directory\n" unless $root->is_dir;
        my @files = sort grep { /\.pm\z/ } map { $_->stringify } _all_files($root);
        for my $file (@files) {
            my $text = path($file)->slurp_utf8;
            my @packages = $text =~ /^\s*package\s+([\w:]+)/mg;
            my $abs = path($file)->absolute->stringify;
            require $abs;    # puff: ignore S016 - rule-paths come from the user's own config
            push @candidates, @packages;
        }
    }

    my ( %seen, %by_code, @classes );
    for my $candidate (@candidates) {
        next if $seen{$candidate}++;
        next if $candidate eq 'Puff::Rule' || !$candidate->isa('Puff::Rule');
        my $code = $candidate->code;
        die "Rule $candidate has invalid code '"
            . ( $code // 'undef' )
            . "' (expected letters followed by three digits)\n"
            unless defined $code && $code =~ $CODE_RE;
        die "Rule $candidate uses code $code, which is reserved for the puff engine\n"
            if $code eq $RESERVED;
        die "Rule $candidate uses code $code, but the prefix ALL is reserved for selecting every rule\n"
            if index( $code, 'ALL' ) == 0;
        if ( my $other = $by_code{$code} ) {
            die "Rules $other and $candidate both use code $code\n";
        }
        $by_code{$code} = $candidate;
        push @classes, $candidate;
    }
    return sort { $a->code cmp $b->code } @classes;
}

sub _all_files ($dir) {
    my @found;
    for my $child ( $dir->children ) {
        push @found, $child->is_dir ? _all_files($child) : $child;
    }
    return @found;
}

sub instantiate ( $class, $classes, %args ) {
    my $all     = sub (@list) { map { $_ eq 'ALL' ? '' : $_ } @list };    # '' is a prefix of every code
    my @select  = $all->( @{ $args{select} // [] }, @{ $args{extend_select} // [] } );
    my @ignore  = $all->( @{ $args{ignore} // [] } );
    my $options = $args{rule_options} // {};

    my @codes = ( $RESERVED, map { $_->code } @$classes );
    for my $selector (@select) {
        die "Unknown rule selector: $selector\n" unless grep { index( $_, $selector ) == 0 } @codes;
    }

    my @rules;
    for my $rule_class ( sort { $a->code cmp $b->code } @$classes ) {
        my $code = $rule_class->code;
        next unless _matches( $code, \@select );
        next if _matches( $code, \@ignore );

        my $given = $options->{$code} // {};
        my $known = $rule_class->options;
        for my $name ( sort keys %$given ) {
            die "Unknown option '$name' for rule $code\n" unless exists $known->{$name};
        }
        push @rules, $rule_class->new( options => $given );
    }
    return @rules;
}

sub _matches ( $code, $prefixes ) {
    return scalar grep { index( $code, $_ ) == 0 } @$prefixes;
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
lists. It dies if a C<select> or C<extend_select> entry is not a
prefix of any loaded rule's code (or of C<P001>) (C<Unknown rule selector:
X>), or if C<rule_options> names an option a selected rule does not declare.
An C<ignore> entry that matches nothing is allowed.

C<load> also dies if a C<Puff::Rule::*> module on C<@INC> fails to compile.

=cut
