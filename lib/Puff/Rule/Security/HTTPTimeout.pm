package Puff::Rule::Security::HTTPTimeout;

use v5.36;
use parent 'Puff::Rule';

use Puff::PPIUtil qw( is_constant_string );
use Scalar::Util  qw( looks_like_number refaddr weaken );

my %LWP = (
    keys         => ['timeout'],
    needs        => ['timeout'],
    setters      => ['timeout'],
    default      => 'the 180s default',
    undef_new    => 'leaves the 180s default',
    undef_setter => 'means no timeout',
);
my %FURL = (
    keys    => ['timeout'],
    needs   => ['timeout'],
    setters => [],
    default => 'the 10s default',
);
my %MOJO = (
    keys    => [qw( connect_timeout inactivity_timeout request_timeout )],
    needs   => [qw( request_timeout inactivity_timeout )],
    setters => [qw( connect_timeout inactivity_timeout request_timeout )],
    default => 'request_timeout defaults to no limit',
);

# Client class => the constructor keys that hold a timeout, the ones that
# count as setting one, the timeout setter methods the client has (those in
# `needs` also count as setting one), what happens without a timeout, and
# what `undef` means as a constructor value and as a setter argument (no
# entry: undef is not checked), and what 0 does when that is not simply no
# timeout.
my %CLIENT = (
    'LWP::UserAgent' => \%LWP,
    'WWW::Mechanize' => \%LWP,
    'HTTP::Tiny'     => {
        %LWP,
        default   => 'the 60s default',
        undef_new => 'leaves the 60s default',
        zero      => 'makes every read and write give up at once',
    },
    'Furl'            => \%FURL,
    'Furl::HTTP'      => \%FURL,
    'Mojo::UserAgent' => \%MOJO,
);

my %DECLARATOR = map { $_ => 1 } qw( my our state );
my %DIE        = map { $_ => 1 } qw( die croak confess );
my %LOOP       = map { $_ => 1 } qw( for foreach );
my %THEN       = map { $_ => 1 } ( ',', '&&', 'and' );
my $ASSIGN     = qr{\A(?:\*\*|<<|>>|&&|\|\||//|[-+*/%x.]|[&|^]\.?)?=\z};
my $INF        = 9**9**9;

sub code            {'S020'}
sub summary         {'HTTP client created without a timeout'}
sub applies_to      { [ 'PPI::Token::Word', 'PPI::Token::Quote' ] }
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
        (`Class->new(...)`, `Class->new({ ... })`, `new Class(...)`,
        `'Class'->new(...)` or `Class::->new(...)`):

        - with no timeout. For Mojo::UserAgent that means neither
          `request_timeout` nor `inactivity_timeout` (either one is
          enough): `request_timeout` defaults to no limit, and
          `connect_timeout` alone does not bound the transfer. A missing
          timeout is reported even when the client's default is short
          (Furl's is 10s, HTTP::Tiny's 60s), so the limit is written down
          where it is used;
        - with a literal timeout of 0, which turns the timeout off in
          LWP::UserAgent and Mojo::UserAgent, and in HTTP::Tiny makes
          every read and write give up at once, or a negative one;
        - with a literal timeout longer than `max-timeout` seconds
          (default 60). For Mojo::UserAgent all three keys are checked;
        - with `timeout => undef` for LWP::UserAgent, WWW::Mechanize or
          HTTP::Tiny, which leaves the default in place.

        A quoted value is checked when the whole string is a number
        (`'300'`, `'1e9'`); other strings, such as `'10 s'`, are not. A
        timeout given as a variable or expression is not reported, nor
        is a call whose arguments the rule cannot read as `key => value`
        pairs, such as `->new(%opts)` or `->new($args)`.

        A missing timeout is not reported when a timeout setter is chained
        onto the constructor (`Mojo::UserAgent->new->request_timeout(10)`)
        or called by a later statement in the same block that starts
        with a setter chain on the client's variable: `$ua->timeout(10);`,
        optionally followed by `, ...`, `&& ...` or `and ...`. The setters are `timeout` for LWP::UserAgent,
        WWW::Mechanize and HTTP::Tiny, and `request_timeout` or
        `inactivity_timeout` for Mojo::UserAgent (`connect_timeout` is
        checked but not enough); Furl has none. The client must be
        assigned to a plain scalar by the whole statement:
        `my $ua = Class->new(...);` (or `our`, `state`, `$ua = ...`,
        `my ($ua) = ...`),
        optionally followed by `or die ...` or `|| die ...`, or as
        `my $ua = $arg // Class->new;` (or `||`). A setter in a nested
        block, sub or condition, one with a statement modifier
        (`... if $x;`), and one after the variable is redeclared (`my`,
        `our`, `state`, `local`, or a `for` loop variable) or assigned
        again (with `=`, `||=`, `//=` or any other assignment operator)
        does not count. Neither does a setter on another variable that
        holds the same client (`my $d = $ua; $d->timeout(10);`).

        Every setter value is checked like a constructor value, even when
        the constructor already sets a good timeout, and is reported at
        the constructor. `->timeout(undef)` is reported for
        LWP::UserAgent, WWW::Mechanize and HTTP::Tiny, where it turns the
        timeout off.

        Subclasses, wrapper functions and class names in a variable are
        not checked.

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
    die "rules.S020.max-timeout must be a positive, finite number\n"
        unless defined $max && !ref $max && looks_like_number($max) && $max > 0 && $max < $INF;
    return $self;
}

sub check ( $self, $elem, $doc ) {
    my $name   = _class_name($elem) // return;
    my $client = $CLIENT{$name} or return;
    my $args   = _constructor_args($elem) // return;
    my $pairs  = _pairs($args);

    my %given;
    for my $pair ( @{ $pairs // [] } ) {
        my ( $key, $value ) = @$pair;
        $given{$key} = $value if grep { $_ eq $key } @{ $client->{keys} };
    }
    for my $key ( @{ $client->{keys} } ) {
        my $value = $given{$key} or next;
        my ( $n, $why ) = $self->_problem( $client, $value, 'undef_new' ) or next;
        return $self->violation( $elem, message => "$name $key => $n $why (CWE-400)" );
    }

    my %setter = map { $_ => 1 } @{ $client->{setters} };
    my @setters
        = grep { $setter{ $_->[0] } } ( _chained_setters($elem), _variable_setters( $elem, $doc ) );
    for my $setter (@setters) {
        my ( $method, $value ) = @$setter;
        my ( $n, $why )        = $self->_problem( $client, $value, 'undef_setter' ) or next;
        return $self->violation( $elem, message => "$name ->$method($n) $why (CWE-400)" );
    }

    return unless $pairs;
    my %needs = map { $_ => 1 } @{ $client->{needs} };
    return if grep { $given{$_} } keys %needs;
    return if grep { $needs{ $_->[0] } } @setters;

    my $max  = $self->option('max-timeout');
    my $what = join ' or ', @{ $client->{needs} };
    return $self->violation(
        $elem,
        message => "$name created without a $what ($client->{default}); set one of at most ${max}s (CWE-400)"
    );
}

# ( shown value, why ) when a timeout value is a problem: undef where the
# client entry $undef says what it means, a literal 0, negative or NaN, or a
# literal over max-timeout. Anything else is accepted.
sub _problem ( $self, $client, $value, $undef ) {
    my ( $shown, $n );
    if ( @$value == 1 ) {
        my $elem = $value->[0];
        if ( $elem->isa('PPI::Token::Word') && $elem->content eq 'undef' ) {
            return $client->{$undef} ? ( 'undef', $client->{$undef} ) : ();
        }
        if ( _is_number($elem) ) {
            $n = $elem->literal;
        }
        elsif ( is_constant_string($elem) && looks_like_number( $elem->string ) ) {
            $n = $elem->string + 0;
        }
        $shown = $elem->content;
    }
    elsif ( @$value == 2 && _is_op( $value->[0], '-' ) && _is_number( $value->[1] ) ) {
        $n     = -$value->[1]->literal;
        $shown = '-' . $value->[1]->content;
    }
    return unless defined $n;
    return ( $shown, 'is not a usable timeout' ) if $n != $n || $n < 0;
    return ( $shown, $client->{zero} // 'means no usable timeout' ) if $n == 0;
    my $max = $self->option('max-timeout');
    return ( $shown, "is longer than max-timeout (${max}s)" ) if $n > $max;
    return;
}

sub _is_number ($elem) {
    return $elem->isa('PPI::Token::Number') && !$elem->isa('PPI::Token::Number::Version') && $elem->can('literal');
}

# The class name a bareword (`Class`, `Class::`) or a constant string
# (`'Class'`) gives, or undef.
sub _class_name ($elem) {
    return $elem->content =~ s/::\z//r if $elem->isa('PPI::Token::Word');
    return unless is_constant_string($elem) && _is_op( $elem->snext_sibling, '->' );
    return $elem->string;
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
    elsif ( _is_indirect_new($prev) ) {
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

sub _is_indirect_new ($prev) {
    return
           $prev
        && $prev->isa('PPI::Token::Word')
        && $prev->content eq 'new'
        && !_is_op( $prev->sprevious_sibling, '->' );
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

# [ method, [ value elements ] ] for each `->name(value)` in the chain
# starting after $el, and the element after the chain. A call without
# arguments (a getter) is not listed.
sub _chain ($el) {
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
    my ($setters) = _chain( _call_end($word) );
    return @$setters;
}

# The setters called on the plain scalar the client is assigned to, by
# later statements in the same statement list that are nothing but a
# setter chain on it, as [ method, [ value elements ] ]. The search stops at
# a statement that declares or assigns the same name again.
sub _variable_setters ( $word, $doc ) {
    my $symbol = _assigned_symbol($word) // return;
    my $stmt   = $word->parent;
    my $index  = _index( $stmt->parent, $doc );
    my $at     = $index->{position}{ refaddr $stmt } // return;
    my $slot   = $index->{slot}{$symbol}{$at}        // return;
    my $uses   = $index->{uses}{$symbol};
    my @setters;
    for my $i ( $slot + 1 .. $#$uses ) {
        my $setters = $uses->[$i][1] or last;
        push @setters, @$setters;
    }
    return @setters;
}

# The symbol of the plain scalar that the statement around the constructor
# on $word assigns it to, or undef. The statement must be
# `[my|our|state] $var = [$term // ]Class->new(...)[->setter(...)]`, with
# `($var)` for `$var`,
# `//` or `||` before the constructor, and optionally `or die ...` or
# `|| die ...` after it.
sub _assigned_symbol ($word) {
    my $stmt = $word->parent;
    return unless $stmt && $stmt->isa('PPI::Statement') && $stmt->parent;
    return
        unless $stmt->parent->isa('PPI::Structure::Block') || $stmt->parent->isa('PPI::Document');

    my ( undef, $after ) = _chain( _call_end($word) );
    if ( $after && !_is_end($after) ) {
        return unless _is_op( $after, 'or' ) || _is_op( $after, '||' );
        my $die = $after->snext_sibling;
        return unless $die && $die->isa('PPI::Token::Word') && $DIE{ $die->content };
    }

    my $start = $word;
    $start = $word->sprevious_sibling if _is_indirect_new( $word->sprevious_sibling );
    my $op = $start->sprevious_sibling;
    if ( _is_op( $op, '//' ) || _is_op( $op, '||' ) ) {
        my $term = $op->sprevious_sibling;
        return unless _is_scalar($term);
        $op = $term->sprevious_sibling;
    }
    return unless _is_op( $op, '=' );
    my $target = $op->sprevious_sibling;
    my $var    = _sole_scalar($target) // return;
    my $first  = $target->sprevious_sibling;
    if ($first) {
        return unless $first->isa('PPI::Token::Word') && $DECLARATOR{ $first->content };
        return if $first->sprevious_sibling;
    }
    return $var->symbol;
}

# $elem when it is a plain scalar, the scalar when $elem is `($scalar)`,
# or undef.
sub _sole_scalar ($elem) {
    return $elem if _is_scalar($elem);
    return unless $elem && $elem->isa('PPI::Structure::List');
    my @children = map { $_->schildren } $elem->schildren;
    return @children == 1 && _is_scalar( $children[0] ) ? $children[0] : undef;
}

sub _is_scalar ($elem) {
    return $elem && $elem->isa('PPI::Token::Symbol') && $elem->raw_type eq '$';
}

sub _is_end ($elem) {
    return $elem->isa('PPI::Token::Structure') && $elem->content eq ';' && !$elem->snext_sibling;
}

# For the statement list $parent: the position of each statement in it; for
# each scalar name the statements that use it, in order, as
# [ position, setters ] (setters undef for a statement that declares or
# assigns the name); and for each name and position where it is declared or
# assigned, that entry's slot in the list, so the setters after a client
# are found without rescanning the list. Built once per statement list and
# document, so a file with many clients is scanned once. The weakened
# reference goes undef when the document is freed, so a re-parsed document
# never sees another's index. The index assumes the engine never changes a
# document between checks: a rule that edited the tree in place would leave
# it describing statements that are gone.
my ( $cached_doc, %cached );

sub _index ( $parent, $doc ) {
    if ( !$cached_doc || refaddr($cached_doc) != refaddr($doc) ) {
        %cached     = ();
        $cached_doc = $doc;
        weaken($cached_doc);
    }
    return $cached{ refaddr $parent } //= _build_index($parent);
}

sub _build_index ($parent) {
    my ( %position, %uses, %slot );
    my $i      = 0;
    my $assign = sub ($symbol) {
        push @{ $uses{$symbol} }, [ $i, undef ];
        $slot{$symbol}{$i} = $#{ $uses{$symbol} };
    };
    for my $stmt ( $parent->schildren ) {
        $position{ refaddr $stmt } = ++$i;
        if ( $stmt->isa('PPI::Statement::Variable') ) {
            $assign->($_) for $stmt->variables;
            next;
        }
        if ( my $var = _loop_variable($stmt) ) {
            $assign->( $var->symbol );
            next;
        }
        next unless ref $stmt eq 'PPI::Statement';
        my $var = $stmt->schild(0) // next;
        if ( $var->isa('PPI::Structure::List') && _is_assign( $var->snext_sibling ) ) {
            $assign->( $_->symbol ) for grep { _is_scalar($_) } @{ $var->find('PPI::Token::Symbol') || [] };
            next;
        }
        next unless _is_scalar($var);
        my $symbol = $var->symbol;
        if ( _is_assign( $var->snext_sibling ) ) {
            $assign->($symbol);
            next;
        }
        my ( $setters, $after ) = _chain($var);
        next unless @$setters && ( !$after || _is_end($after) || _is_op( $after, keys %THEN ) );
        push @{ $uses{$symbol} }, [ $i, $setters ];
        $assign->($symbol) if $after && _assigns( $after, $symbol );
    }
    return { position => \%position, uses => \%uses, slot => \%slot };
}

# The scalar a `for`/`foreach` loop statement sets, or undef.
sub _loop_variable ($stmt) {
    return unless $stmt->isa('PPI::Statement::Compound');
    my $word = $stmt->schild(0);
    return unless $word->isa('PPI::Token::Word') && $LOOP{ $word->content };
    my $var = $word->snext_sibling;
    $var = $var->snext_sibling if $var && $var->isa('PPI::Token::Word') && $DECLARATOR{ $var->content };
    return _is_scalar($var) ? $var : undef;
}

# Whether $el or a later sibling declares or assigns the scalar $symbol.
sub _assigns ( $el, $symbol ) {
    for ( ; $el ; $el = $el->snext_sibling ) {
        my @symbols = $el->isa('PPI::Node') ? @{ $el->find('PPI::Token::Symbol') || [] } : ($el);
        for my $s ( grep { _is_scalar($_) && $_->symbol eq $symbol } @symbols ) {
            my $prev = $s->sprevious_sibling;
            return 1 if _is_assign( $s->snext_sibling );
            return 1
                if $prev
                && $prev->isa('PPI::Token::Word')
                && ( $DECLARATOR{ $prev->content } || $prev->content eq 'local' );
        }
    }
    return 0;
}

sub _is_assign ($elem) {
    return $elem && $elem->isa('PPI::Token::Operator') && $elem->content =~ $ASSIGN;
}

sub _is_op ( $elem, @ops ) {
    return unless $elem && $elem->isa('PPI::Token::Operator');
    my $content = $elem->content;
    return grep { $_ eq $content } @ops;
}

1;

# ABSTRACT: S020 - HTTP client created without a timeout

__END__

=pod

=head1 DESCRIPTION

Reports an HTTP client constructor (LWP::UserAgent, WWW::Mechanize,
HTTP::Tiny, Furl, Furl::HTTP or Mojo::UserAgent) with no timeout, a literal
timeout of 0 or less, or a literal timeout longer than the C<max-timeout>
option (default 60 seconds). A slow or stalled server can otherwise hold a
worker for minutes or forever (CWE-400). The violation is reported at the
class name. There is no fix, and the rule is selected only by its exact code
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
is C<timeout>. For Mojo::UserAgent either C<request_timeout> or
C<inactivity_timeout> is enough; C<connect_timeout> only bounds the
connect, so on its own it does not count, but a literal value for it is
still checked. Arguments may be a list (C<< ->new(timeout => 10) >>), a
hash reference (C<< ->new({ timeout => 10 }) >>, as Mojo::UserAgent
accepts) or the indirect form C<new LWP::UserAgent(timeout => 10)>. The
class name may also be quoted (C<< 'LWP::UserAgent'->new >>) or end in
C<::> (C<< LWP::UserAgent::->new >>). When a
key is given more than once the last one wins, as in Perl.

=head2 Values

=over

=item *

A literal C<0> is reported for every client: it turns the timeout off in
LWP::UserAgent and Mojo::UserAgent. In HTTP::Tiny every read and write
gives up at once unless the socket is already ready, and so does the
connect with IO::Socket::IP (the socket class HTTP::Tiny prefers); with
IO::Socket::INET the connect has no limit.

=item *

A negative literal (C<< timeout => -5 >>) is reported as not a usable
timeout.

=item *

C<< timeout => undef >> is reported for LWP::UserAgent, WWW::Mechanize and
HTTP::Tiny, where it leaves the default (180 or 60 seconds), and
C<< ->timeout(undef) >> for the same clients, where it turns the timeout
off. For Furl and Mojo::UserAgent C<undef> is not checked.

=item *

A quoted value is checked when the whole string is a number, as
L<Scalar::Util/looks_like_number> sees it (C<'300'>, C<'1e9'>). Other
strings, such as C<'10 s'>, are not checked.

=item *

A value that is not a literal (C<< timeout => $t >>,
C<< timeout => 2 * $n >>) is not checked.

=back

=head2 Setters

A missing timeout is not reported when a timeout setter is chained onto the
constructor (C<< Mojo::UserAgent->new->request_timeout(10) >>), or called
on the variable the client is assigned to by a later statement in the same
block (or at the same file level) that starts with a setter chain on that
variable: C<< $ua->timeout(10); >>, or the same followed by C<, ...>,
C<&& ...> or C<and ...>, as in C<< $ua->timeout(10), $ua->get($url); >>.
The setters are:

=over

=item * LWP::UserAgent, WWW::Mechanize and HTTP::Tiny: C<timeout>.

=item * Mojo::UserAgent: C<request_timeout> or C<inactivity_timeout>.
C<connect_timeout> is checked but does not count.

=item * Furl and Furl::HTTP: none, so the timeout must be in the
constructor.

=back

The client must be assigned to a plain scalar by the whole statement:
C<my $ua = Class-E<gt>new(...);>, with C<our>, C<state> or no declarator,
or C<< my ($ua) = Class->new(...); >>, optionally followed by C<or die ...> or C<|| die ...> (C<croak> and
C<confess> too), or as C<< my $ua = $arg // Class->new; >> (or C<||>).

These do not count: a setter in a nested block, sub, loop or condition
(C<< if ($x) { $ua->timeout(10) } >>); one with a statement modifier
(C<< $ua->timeout(10) if $x; >>); one before the constructor; one after the
same name is declared again (with C<my>, C<our>, C<state>, C<local> or as a
C<for> loop variable) or assigned again (with C<=>, C<||=>, C<//=> or any
other assignment operator, even later in the setter's own statement); one
on another variable holding the same client
(C<< my $d = $ua; $d->timeout(10); >>); and a call without arguments.

Every setter value is checked like a constructor value, even when the
constructor already sets a good timeout
(C<< ->new(timeout => 5); $ua->timeout(0); >> is reported), and the
violation is reported at the constructor.

=head2 Not checked

=over

=item *

Arguments that are not all C<< key => value >> pairs with constant keys,
such as C<< ->new(%opts) >>, C<< ->new($args) >> or
C<< ->new(%defaults, timeout => 5) >>: the rule cannot tell what they hold.
Setter values are still checked.

=item *

Subclasses other than those listed, wrapper functions that build a client,
and class names held in a variable.

=item *

A client assigned anywhere else (C<< $self->{ua} = ... >>,
C<< my ( $ua, $x ) = ... >>) or used without being stored
(C<< LWP::UserAgent->new->get($url) >>) needs its timeout in the
constructor or in a chained setter.

=back

=head2 Options

    [rules.S020]
    max-timeout = 30

C<max-timeout> is the longest acceptable literal timeout in seconds. It must
be a positive, finite number. Default 60.

=cut
