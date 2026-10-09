package Puff::Rule::Security::HTTPTimeout;

use v5.36;
use parent 'Puff::Rule';

use Puff::LexicalScopes qw( declarations );
use Puff::PPIUtil       qw( is_constant_string );
use Scalar::Util        qw( looks_like_number refaddr );

my %LWP  = ( keys => ['timeout'], needs => ['timeout'], default => 'the 180s default' );
my %MOJO = (
    keys    => [qw( connect_timeout inactivity_timeout request_timeout )],
    needs   => [qw( request_timeout inactivity_timeout )],
    default => 'request_timeout defaults to no limit',
);

# Client class => the constructor keys (and setter methods) that hold a
# timeout, the ones that count as setting one, and what happens without.
my %CLIENT = (
    'LWP::UserAgent'  => \%LWP,
    'WWW::Mechanize'  => \%LWP,
    'HTTP::Tiny'      => { %LWP, default => 'the 60s default' },
    'Furl'            => { %LWP, default => 'the 10s default' },
    'Furl::HTTP'      => { %LWP, default => 'the 10s default' },
    'Mojo::UserAgent' => \%MOJO,
);

sub code            {'S020'}
sub summary         {'HTTP client created without a timeout'}
sub applies_to      {'PPI::Token::Word'}
sub cwe             {400}
sub explicit_select {1}
sub options         { { 'max-timeout' => 60 } }

sub explanation {
    return <<~'END';
        An HTTP client with no timeout, or a very long one, lets a slow or
        stalled server hold a worker for as long as it likes. Enough of
        those and the service stops answering (CWE-400, uncontrolled
        resource consumption).

        The rule reports a call to `new` on LWP::UserAgent,
        WWW::Mechanize, HTTP::Tiny, Furl, Furl::HTTP or Mojo::UserAgent
        (`Class->new(...)`, `Class->new({ ... })` or `new Class(...)`):

        - with no timeout. For Mojo::UserAgent that means neither
          `request_timeout` nor `inactivity_timeout`: `request_timeout`
          defaults to no limit, and `connect_timeout` alone does not bound
          the transfer. A missing timeout is reported even when the
          client's default is short (Furl's is 10s, HTTP::Tiny's 60s), so
          the limit is written down where it is used;
        - with a literal timeout of 0, which turns the timeout off in
          LWP::UserAgent and Mojo::UserAgent, and in HTTP::Tiny leaves the
          connect unbounded;
        - with a literal timeout longer than `max-timeout` seconds
          (default 60). For Mojo::UserAgent all three keys are checked.

        A timeout given as a variable or expression is not reported, nor
        is a call whose arguments the rule cannot read as `key => value`
        pairs, such as `->new(%opts)` or `->new($args)`.

        The constructor is not reported when the client is assigned to a
        plain scalar (`my $ua = Class->new;`, or `$ua = ...;`) and a
        setter (`->timeout(...)`, or for Mojo::UserAgent
        `->request_timeout(...)` or `->inactivity_timeout(...)`) is called
        on that variable later in the same block, or chained onto the
        constructor (`Mojo::UserAgent->new->request_timeout(10)`). A
        setter given a literal 0 or a value over `max-timeout` is reported
        in the same way as the constructor key. A setter on a different
        variable of the same name declared in an inner block does not
        count. A client stored anywhere else (`$self->{ua} = ...`, or
        used straight away as in `LWP::UserAgent->new->get($url)`) needs
        the timeout in the constructor.

        Change the longest acceptable timeout with:

            [rules.S020]
            max-timeout = 30

        There is no fix: pick a timeout that suits the service. The rule
        is selected only by its code or `ALL`.
        END
}

sub new ( $class, %args ) {
    my $self = $class->SUPER::new(%args);
    my $max  = $self->option('max-timeout');
    die "rules.S020.max-timeout must be a positive number\n"
        unless defined $max && !ref $max && looks_like_number($max) && $max > 0;
    return $self;
}

sub check ( $self, $elem, $doc ) {
    my $client = $CLIENT{ $elem->content } or return;
    my $args   = _constructor_args($elem) // return;
    my $pairs  = _pairs($args)            // return;
    my $name   = $elem->content;

    my %given;
    for my $pair (@$pairs) {
        my ( $key, $value ) = @$pair;
        next unless grep { $_ eq $key } @{ $client->{keys} };
        $given{$key} = $value;
    }
    for my $key ( @{ $client->{keys} } ) {
        my $value = $given{$key} or next;
        my ( $n, $why ) = $self->_problem($value) or next;
        return $self->violation( $elem, message => "$name $key => $n $why (CWE-400)" );
    }
    return if grep { $given{$_} } @{ $client->{needs} };

    my @setters = ( _chained_setters($elem), _variable_setters( $elem, $client ) );
    for my $setter (@setters) {
        my ( $method, $value ) = @$setter;
        next unless grep { $_ eq $method } @{ $client->{keys} };
        my ( $n, $why ) = $self->_problem($value) or next;
        return $self->violation( $elem, message => "$name ->$method($n) $why (CWE-400)" );
    }
    my %needs = map { $_ => 1 } @{ $client->{needs} };
    return if grep { $needs{ $_->[0] } } @setters;

    my $max  = $self->option('max-timeout');
    my $what = join ' or ', @{ $client->{needs} };
    return $self->violation(
        $elem,
        message => "$name created without a $what ($client->{default}); set one of at most ${max}s (CWE-400)"
    );
}

# ( number, why ) when a timeout value is a problem: a literal 0, or a
# literal over max-timeout. Anything that is not a literal number is accepted.
sub _problem ( $self, $value ) {
    return unless @$value == 1;
    my $elem = $value->[0];
    my $n;
    if ( $elem->isa('PPI::Token::Number') ) {
        $n = $elem->can('literal') ? $elem->literal : undef;
    }
    elsif ( is_constant_string($elem) && $elem->string =~ /\A\s*([0-9]+(?:\.[0-9]+)?)\s*\z/ ) {
        $n = $1;
    }
    return unless defined $n;
    return ( 0, q{means no usable timeout} ) if $n == 0;
    my $max = $self->option('max-timeout');
    return ( $n, "is longer than max-timeout (${max}s)" ) if $n > $max;
    return;
}

# The argument list of the constructor call on the class name $word, as a
# list of elements: [] when there is none, undef when $word is not a
# constructor call.
sub _constructor_args ($word) {
    my $next = $word->snext_sibling;
    my $prev = $word->sprevious_sibling;
    my $list;
    if ( _is_op( $next, '->' ) ) {
        my $method = $next->snext_sibling;
        return unless $method && $method->isa('PPI::Token::Word') && $method->content eq 'new';
        $list = $method->snext_sibling;
    }
    elsif ( $prev && $prev->isa('PPI::Token::Word') && $prev->content eq 'new' ) {
        my $before = $prev->sprevious_sibling;
        return if _is_op( $before, '->' );
        $list = $next;
    }
    else {
        return;
    }
    return [] unless $list && $list->isa('PPI::Structure::List');
    my @elements = _contents($list);
    if (   @elements == 1
        && $elements[0]->isa('PPI::Structure::Constructor')
        && $elements[0]->start
        && $elements[0]->start->content eq '{' ) {
        @elements = _contents( $elements[0] );
    }
    return \@elements;
}

sub _contents ($structure) {
    return map { $_->schildren } grep { $_->isa('PPI::Statement') } $structure->schildren;
}

# The elements as [ key, [ value elements ] ] pairs, or undef when they are
# not all `key => value` with a constant key.
sub _pairs ($elements) {
    my @args = ( [] );
    for my $el (@$elements) {
        if ( _is_op( $el, ',' ) || _is_op( $el, '=>' ) ) {
            push @args, [];
            next;
        }
        push @{ $args[-1] }, $el;
    }
    pop @args unless @{ $args[-1] };
    return if @args % 2;
    my @pairs;
    while ( my ( $key, $value ) = splice @args, 0, 2 ) {
        return unless @$key == 1 && @$value;
        my $k = $key->[0];
        my $name
            = $k->isa('PPI::Token::Word') ? $k->content
            : is_constant_string($k)      ? $k->string
            :                               return;
        push @pairs, [ $name, $value ];
    }
    return \@pairs;
}

# The end of the constructor call: the `new` word, or its argument list.
sub _call_end ($word) {
    my $next = $word->snext_sibling;
    my $end  = _is_op( $next, '->' ) ? $next->snext_sibling : $word;
    my $list = $end->snext_sibling;
    return $list && $list->isa('PPI::Structure::List') ? $list : $end;
}

# [ method, [ value elements ] ] for each `->name(value)` chained onto the
# constructor, and the element after the chain.
sub _chain ($word) {
    my $el = _call_end($word);
    my @setters;
    while ( _is_op( $el->snext_sibling, '->' ) ) {
        my $method = $el->snext_sibling->snext_sibling;
        last unless $method && $method->isa('PPI::Token::Word');
        my $list = $method->snext_sibling;
        last unless $list && $list->isa('PPI::Structure::List');
        my @value = _contents($list);
        push @setters, [ $method->content, \@value ] if @value;
        $el = $list;
    }
    return ( \@setters, $el->snext_sibling );
}

sub _chained_setters ($word) {
    my ($setters) = _chain($word);
    return @$setters;
}

# The setters called on the plain scalar the client is assigned to, later
# in the same block, as [ method, [ value elements ] ].
sub _variable_setters ( $word, $client ) {
    my ( undef, $after ) = _chain($word);
    return unless $after && $after->isa('PPI::Token::Structure') && $after->content eq ';';
    my $op = $word->sprevious_sibling;
    $op = $op->sprevious_sibling if $op && $op->isa('PPI::Token::Word') && $op->content eq 'new';
    return unless _is_op( $op, '=' );
    my $var = $op->sprevious_sibling;
    return unless $var && $var->isa('PPI::Token::Symbol') && $var->raw_type eq '$';
    my $declarator = $var->sprevious_sibling;
    return
        if $declarator && !( $declarator->isa('PPI::Token::Word') && $declarator->content =~ /\A(?:my|our|state)\z/ );
    return if $declarator && $declarator->sprevious_sibling;

    my $stmt  = $word->statement;
    my $scope = $stmt->parent;
    return unless $scope && ( $scope->isa('PPI::Structure::Block') || $scope->isa('PPI::Document') );
    my $symbol = $var->symbol;
    my $loc    = $word->location;

    my $uses = $scope->find(
        sub ( $top, $el ) {
            return 0 unless $el->isa('PPI::Token::Symbol') && $el->symbol eq $symbol;
            return 0 unless _before( $loc, $el->location );
            return _is_op( $el->snext_sibling, '->' ) ? 1 : 0;
        }
    ) || [];
    my @others = grep { refaddr( $_->{elem} ) != refaddr($var) } map { declarations($_) } @{
        $scope->find(
            sub ( $top, $el ) {
                $el->isa('PPI::Token::Word') && $el->content =~ /\A(?:my|our|state)\z/;
            }
            )
            || []
    };

    my @setters;
    for my $use (@$uses) {
        next
            if grep {
            $_->{symbol} eq $symbol && _before( $_->{elem}->location, $use->location ) && _contains( $_->{scope}, $use )
            } @others;
        my $method = $use->snext_sibling->snext_sibling;
        next unless $method && $method->isa('PPI::Token::Word');
        my $list = $method->snext_sibling;
        next unless $list && $list->isa('PPI::Structure::List');
        my @value = _contents($list);
        push @setters, [ $method->content, \@value ] if @value;
    }
    return @setters;
}

sub _is_op ( $elem, $op ) {
    return $elem && $elem->isa('PPI::Token::Operator') && $elem->content eq $op;
}

sub _before ( $at, $loc ) {
    return $at->[0] < $loc->[0] || ( $at->[0] == $loc->[0] && $at->[1] < $loc->[1] );
}

sub _contains ( $outer, $elem ) {
    for ( my $el = $elem ; $el ; $el = $el->parent ) {
        return 1 if refaddr($el) == refaddr($outer);
    }
    return 0;
}

1;

# ABSTRACT: S020 - HTTP client created without a timeout

__END__

=pod

=head1 DESCRIPTION

Reports an HTTP client constructor (LWP::UserAgent, WWW::Mechanize,
HTTP::Tiny, Furl, Furl::HTTP or Mojo::UserAgent) with no timeout, a literal
timeout of 0, or a literal timeout longer than the C<max-timeout> option
(default 60 seconds). A slow or stalled server can otherwise hold a worker
for minutes or forever (CWE-400). The violation is reported at the class
name. There is no fix, and the rule is selected only by its exact code
(C<S020>) or C<ALL>.

=head2 Rationale

LWP::UserAgent (and WWW::Mechanize, which inherits it) waits 180 seconds by
default, HTTP::Tiny 60 and Furl 10. Mojo::UserAgent's C<request_timeout>
defaults to 0, no limit, so a server that sends a byte every few seconds can
keep a request going indefinitely despite the 40 second
C<inactivity_timeout>. The rule asks for the timeout to be written down
where the client is made, so a missing timeout is reported even when the
client's default is shorter than C<max-timeout>.

=head2 What counts as a timeout

For LWP::UserAgent, WWW::Mechanize, HTTP::Tiny, Furl and Furl::HTTP the key
is C<timeout>. For Mojo::UserAgent it is C<request_timeout> or
C<inactivity_timeout>; C<connect_timeout> only bounds the connect, so on
its own it does not count, but a literal value for it is still checked.
Arguments may be a list (C<< ->new(timeout => 10) >>), a hash reference
(C<< ->new({ timeout => 10 }) >>, as Mojo::UserAgent accepts) or the
indirect form C<new LWP::UserAgent(timeout => 10)>. When a key is given
more than once the last one wins, as in Perl.

=head2 Edge cases

=over

=item *

A value that is not a literal number (C<< timeout => $t >>,
C<< timeout => 2 * $n >>, C<< timeout => -1 >>) is not checked. A quoted
number (C<< timeout => '300' >>) is.

=item *

A literal C<0> is reported for every client: it turns the timeout off in
LWP::UserAgent and Mojo::UserAgent, and in HTTP::Tiny it leaves the
connect without a limit while reads stop waiting at once.

=item *

Arguments that are not all C<< key => value >> pairs with constant keys,
such as C<< ->new(%opts) >>, C<< ->new($args) >> or
C<< ->new(%defaults, timeout => 5) >>, are not reported: the rule cannot
tell what they hold.

=item *

A setter chained onto the constructor
(C<< Mojo::UserAgent->new->request_timeout(10) >>) counts. So does one
called later in the same block on the plain scalar the client is assigned
to, by C<my $ua = ...;>, C<our>, C<state> or a plain C<$ua = ...;>. A
setter that comes before the constructor, sits on a different variable of
the same name declared in a nested block (or redeclared later in the same
one), or is called without arguments does not count. Setter values are
checked like constructor values.

=item *

A client assigned anywhere else (C<< $self->{ua} = ... >>,
C<< my ($ua) = ... >>) or used without being stored
(C<< LWP::UserAgent->new->get($url) >>) needs its timeout in the
constructor or in a chained setter.

=item *

Subclasses other than those listed, and class names held in a variable,
are not recognised.

=back

=head2 Options

    [rules.S020]
    max-timeout = 30

C<max-timeout> is the longest acceptable literal timeout in seconds. It must
be a positive number. Default 60.

=cut
