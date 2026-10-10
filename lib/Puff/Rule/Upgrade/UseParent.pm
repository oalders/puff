package Puff::Rule::Upgrade::UseParent;

use v5.36;
use parent 'Puff::Rule';

use Puff::PPIUtil qw( is_constant_string );

sub code       {'U001'}
sub summary    {'use base instead of use parent'}
sub applies_to {'PPI::Statement::Include'}
sub fix_safety {'unsafe'}

sub explanation {
    return <<~'END';
        `use base` sets up inheritance, but it also swallows errors: when
        loading a parent class fails because the file is missing, base
        carries on as long as the package has something in it, so a typo
        or a broken install can go unnoticed. It also carries support for
        the `fields` pragma that almost no code needs. `use parent` does
        the same job and fails loudly:

            use parent 'My::Base';

        For a parent class declared in the same file, which has no file of
        its own to load, write `use parent -norequire, 'My::Base';`. The
        same goes for core classes that live in another module's file, such
        as Tie::StdHash in Tie::Hash: load that module, then use
        `-norequire`.

        The fix replaces `base` with `parent`, adding `-norequire` when
        every parent class is a package declared in this file or a
        Tie::StdHash, Tie::ExtraHash, Tie::StdArray or Tie::StdScalar whose
        module the file loads. It is not offered when some parents are
        declared in the file and others are not, when a Tie::Std* parent's
        module is not loaded, or when the parents are not constant strings.
        It is unsafe because `use parent` dies where `use base` quietly
        went on: a parent whose file cannot be loaded, or one declared in
        another file that was loaded earlier, now stops the program.
        Classes that rely on `fields` inheritance need `use base`.
        END
}

# Core packages that live in another module's file.
my %HOME = (
    'Tie::StdHash'   => 'Tie::Hash',
    'Tie::ExtraHash' => 'Tie::Hash',
    'Tie::StdArray'  => 'Tie::Array',
    'Tie::StdScalar' => 'Tie::Scalar',
);

sub check ( $self, $elem, $doc ) {
    return unless ( $elem->type // q{} ) eq 'use' && ( $elem->module // q{} ) eq 'base';
    return $self->violation(
        $elem,
        message => 'Use parent instead of base',
        fixable => defined _norequire( $elem, $doc ) ? 1 : 0,
    );
}

sub fix ( $self, $violation, $fix ) {
    my $include   = $violation->element;
    my $norequire = _norequire( $include, $include->top ) // return 0;
    my $word      = $include->schild(1);
    $fix->replace( $word, 'parent' );
    if ($norequire) {
        my ($first) = _arguments($include);
        $fix->insert_before( $first, '-norequire, ' );
    }
    return 1;
}

# 1 if every parent is declared in $doc, 0 if none is, undef if the fix
# cannot tell or the parents are mixed.
sub _norequire ( $include, $doc ) {
    my @args = _arguments($include) or return;
    my @names;
    for my $arg (@args) {
        if ( $arg->isa('PPI::Token::QuoteLike::Words') ) {
            push @names, $arg->literal;
        }
        elsif ( $arg->isa('PPI::Token::Quote') && is_constant_string($arg) ) {
            push @names, $arg->string;
        }
        else {
            return;
        }
    }
    return unless @names;
    my %local  = map { $_->namespace         => 1 } @{ $doc->find('PPI::Statement::Package') || [] };
    my %loaded = map { ( $_->module // q{} ) => 1 } @{ $doc->find('PPI::Statement::Include') || [] };
    for my $name (@names) {
        next unless $HOME{$name};
        return unless $loaded{ $HOME{$name} };
        $local{$name} = 1;
    }
    my $found = grep { $local{$_} } @names;
    return 0 if !$found;
    return 1 if $found == @names;
    return;
}

# The argument elements after `use base`, without commas.
sub _arguments ($include) {
    my @parts = $include->schildren;
    splice @parts, 0, 2;
    pop @parts if @parts && $parts[-1]->isa('PPI::Token::Structure') && $parts[-1]->content eq ';';
    if ( @parts == 1 && $parts[0]->isa('PPI::Structure::List') ) {
        my ($expr) = $parts[0]->schildren;
        @parts = $expr ? $expr->schildren : ();
    }
    return grep { !( $_->isa('PPI::Token::Operator') && ( $_->content eq ',' || $_->content eq '=>' ) ) } @parts;
}

1;

# ABSTRACT: U001 - use base instead of use parent

__END__

=pod

=head1 DESCRIPTION

Reports C<use base>, which hides errors from loading a parent class. The
unsafe fix rewrites it as C<use parent>, with C<-norequire> when every parent
is declared in the same file.

Based on L<Perl::Critic::Policy::Tics::ProhibitUseBase>.

Not selected by default; select it with C<U> or C<U001>.

=cut
