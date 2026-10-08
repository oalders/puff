package Puff::Rule::Builtins::DollarAB;

use v5.36;
use parent 'Puff::Rule';

my @PAIR_FUNCTIONS = qw( sort reduce reductions pairgrep pairfirst pairmap pairwise );

sub code       {'A001'}
sub summary    {'Do not use $a or $b outside sort and pair functions'}
sub applies_to {'PPI::Token::Symbol'}
sub options    { { 'extra-pair-functions' => [] } }

sub explanation {
    return <<~'END';
        $a and $b are package variables that sort, List::Util's reduce,
        reductions, pairgrep, pairfirst and pairmap, and List::MoreUtils'
        pairwise set for their block. Using them as ordinary variables is
        confusing, and `my $a` hides the package variable from any sort block
        in its scope, which then compares undef.

        The rule reports $a and $b unless they are inside a block passed
        directly to one of those functions (`sort { $a <=> $b } @x`,
        `List::Util::reduce { $a + $b } @x`), or inside a named sub that the
        file passes to sort by name (`sort by_num @x`). $a[0], $a{x}, @a and
        $main::a are different variables and are not reported.

        To allow other functions that set $a and $b, list them in
        .puff.toml:

            [rules.A001]
            extra-pair-functions = ["pairfoo"]

        There is no fix: renaming a variable safely needs every use of it.

        This rule is not selected by default. Turn it on with `--select A` or
        `extend-select = ["A"]`. Based on Perl::Critic::Policy::Community::DollarAB.
        END
}

sub new ( $class, %args ) {
    my $self  = $class->SUPER::new(%args);
    my $extra = $self->option('extra-pair-functions');
    die "rules.A001.extra-pair-functions must be a list of function names\n"
        unless ref $extra eq 'ARRAY' && !grep { !defined || ref || !/\A\w+\z/ } @$extra;
    $self->{pair_functions} = { map { $_ => 1 } @PAIR_FUNCTIONS, @$extra };
    return $self;
}

sub check ( $self, $elem, $doc ) {
    my $symbol = $elem->symbol;
    return unless $symbol eq '$a' || $symbol eq '$b';
    return if $self->_in_pair_block( $elem, $doc );
    return $self->violation( $elem, message => "$symbol is reserved for sort and pair functions; use another name" );
}

sub _in_pair_block ( $self, $elem, $doc ) {
    for ( my $node = $elem->parent ; $node ; $node = $node->parent ) {
        next unless $node->isa('PPI::Structure::Block');
        my $prev = $node->sprevious_sibling;
        if ( $prev && $prev->isa('PPI::Token::Word') ) {
            my ($name) = $prev->content =~ /(\w+)\z/;
            return 1 if $self->{pair_functions}{$name};
        }
        my $parent = $node->parent;
        if ( $parent && $parent->isa('PPI::Statement::Sub') && defined( my $sub = $parent->name ) ) {
            return 1 if _sort_subs($doc)->{$sub};
        }
    }
    return 0;
}

# Names of subs the document passes to sort by name: `sort NAME LIST` or
# `sort(NAME LIST)`.
sub _sort_subs ($doc) {
    my %names;
    for my $word ( @{ $doc->find( sub { $_[1]->isa('PPI::Token::Word') && $_[1]->content eq 'sort' } ) || [] } ) {
        my $next = $word->next_token;
        $next = $next->next_token
            while $next && ( !$next->significant || ( $next->isa('PPI::Token::Structure') && $next->content eq '(' ) );
        $names{ $next->content } = 1 if $next && $next->isa('PPI::Token::Word');
    }
    return \%names;
}

1;

# ABSTRACT: A001 - do not use $a or $b outside sort and pair functions

__END__

=pod

=head1 DESCRIPTION

Reports C<$a> and C<$b> outside a block passed directly to C<sort>,
C<reduce>, C<reductions>, C<pairgrep>, C<pairfirst>, C<pairmap> or
C<pairwise> (or a function listed in the C<extra-pair-functions> option),
and outside a named sub the file uses as C<sort NAME>. There is no fix.

Not selected by default; select it with C<A> or C<A001>. Based on
L<Perl::Critic::Policy::Community::DollarAB>, which accepts any earlier
C<sort> in the file as context; this rule only accepts the block passed to
the function.

=cut
