use v5.36;
use Test2::V0;

use Puff::Engine ();
use Puff::Source ();

# Test-only rules: each flags one bareword and rewrites it.
package WordRule {
    use v5.36;
    use parent 'Puff::Rule';

    sub applies_to {'PPI::Token::Word'}
    sub from       { die 'override' }
    sub to         { die 'override' }

    sub check ( $self, $elem, $doc ) {
        return unless $elem->content eq $self->from;
        return $self->violation( $elem, message => 'found ' . $self->from );
    }

    sub fix ( $self, $violation, $fix ) {
        $fix->replace( $violation->element, $self->to );
        return 1;
    }
}

package T001 {
    use parent -norequire, 'WordRule';
    sub code       {'T001'}
    sub fix_safety {'safe'}
    sub from       {'foo'}
    sub to         {'bar'}
}

package T002 {
    use parent -norequire, 'WordRule';
    sub code       {'T002'}
    sub fix_safety {'unsafe'}
    sub from       {'baz'}
    sub to         {'qux'}
}

package T003 {    # flags what T004's fix produces
    use parent -norequire, 'WordRule';
    sub code       {'T003'}
    sub fix_safety {'safe'}
    sub from       {'foo2'}
    sub to         {'done'}
}

package T004 {
    use parent -norequire, 'WordRule';
    sub code       {'T004'}
    sub fix_safety {'safe'}
    sub from       {'foo'}
    sub to         {'foo2'}
}

package T005 {    # toggles a and b forever
    use v5.36;
    use parent -norequire, 'WordRule';
    sub code       {'T005'}
    sub fix_safety {'safe'}

    sub check ( $self, $elem, $doc ) {
        return unless $elem->content =~ /\A[ab]\z/;
        return $self->violation( $elem, message => 'a or b' );
    }

    sub fix ( $self, $violation, $fix ) {
        $fix->replace( $violation->element, $violation->element->content eq 'a' ? 'b' : 'a' );
        return 1;
    }
}

package T006 {    # fix dies
    use v5.36;
    use parent -norequire, 'WordRule';
    sub code       {'T006'}
    sub fix_safety {'safe'}
    sub from       {'boom'}
    sub fix ( $self, $violation, $fix ) { die "nope\n" }
}

package main;

sub engine ( $mode, @classes ) {
    return Puff::Engine->new( rules => [ map { $_->new } @classes ], fix_mode => $mode );
}

sub run_engine ( $engine, $text ) {
    return $engine->process_source( Puff::Source->from_string($text), file => 'x.pl' );
}

sub summary ($result) {
    return [ map { [ $_->code, $_->line, $_->column ] } @{ $result->{violations} } ];
}

subtest 'lint only' => sub {
    my $text   = "baz; foo;\nfoo; # puff: ignore T001\n# puff: ignore\nfoo;\n";
    my $result = run_engine( engine( 'none', qw( T002 T001 ) ), $text );
    is( summary($result), [ [ 'T002', 1, 1 ], [ 'T001', 1, 6 ], [ 'P001', 3, 1 ], [ 'T001', 4, 1 ] ],
        'sorted by line and column, suppressed dropped, P001 included' );
    is( [ map { $_->file } @{ $result->{violations} } ], [ ('x.pl') x 4 ], 'file set' );
    my ($p001) = grep { $_->code eq 'P001' } @{ $result->{violations} };
    is( $p001->fixable, 0, 'P001 is not fixable' );
    is( $p001->message, 'suppression comment must list codes', 'P001 message' );
    is( $result->{new_text},      undef, 'no new text' );
    is( $result->{fixed_count},   0,     'nothing fixed' );
    is( $result->{error},         undef, 'no error' );
    is( $result->{fixes_skipped}, undef, 'fixes not skipped' );
};

subtest 'P001 cannot be suppressed' => sub {
    my $result = run_engine( engine( 'none', 'T001' ), "# puff: ignore-file P001\n# puff: ignore\n" );
    is( summary($result), [ [ 'P001', 2, 1 ] ], 'P001 still reported' );
};

subtest 'safe mode' => sub {
    my $result = run_engine( engine( 'safe', qw( T001 T002 ) ), "foo; baz;\nfoo;\n" );
    is( $result->{new_text},    "bar; baz;\nbar;\n", 'T001 fixed, T002 left' );
    is( summary($result),       [ [ 'T002', 1, 6 ] ], 'T002 still reported' );
    is( $result->{fixed_count}, 2,                    'two fixed' );
    is( $result->{error},       undef,                'no error' );
};

subtest 'unsafe mode' => sub {
    my $result = run_engine( engine( 'unsafe', qw( T001 T002 ) ), "foo; baz;\n" );
    is( $result->{new_text},    "bar; qux;\n", 'both fixed' );
    is( summary($result),       [],            'nothing left' );
    is( $result->{fixed_count}, 2,             'two fixed' );
};

subtest 'nothing fixable leaves new_text undef' => sub {
    my $result = run_engine( engine( 'safe', 'T002' ), "baz;\n" );
    is( $result->{new_text},    undef, 'unchanged' );
    is( $result->{fixed_count}, 0,     'nothing fixed' );
    is( summary($result), [ [ 'T002', 1, 1 ] ], 'still reported' );
};

subtest 'fix loop' => sub {
    my $result = run_engine( engine( 'safe', qw( T003 T004 ) ), "foo;\n" );
    is( $result->{new_text},    "done;\n", 'second pass fixed what the first produced' );
    is( summary($result),       [],        'nothing left' );
    is( $result->{fixed_count}, 1,         'original count minus remaining' );
};

subtest 'pass cap' => sub {
    my $result = run_engine( engine( 'safe', 'T005' ), "a;\n" );
    is( $result->{error},    'fix loop did not converge', 'error' );
    is( $result->{new_text}, undef,                       'original kept' );
    is( $result->{fixed_count}, 0, 'nothing fixed' );
    is( summary($result), [ [ 'T005', 1, 1 ] ], 'violations of the original text' );
};

subtest 'CRLF' => sub {
    my $result = run_engine( engine( 'unsafe', 'T001' ), "foo;\r\nfoo;\r\n" );
    is( summary($result), [ [ 'T001', 1, 1 ], [ 'T001', 2, 1 ] ], 'violations reported' );
    like( $result->{fixes_skipped}, qr/CRLF/, 'fixes_skipped set' );
    is( $result->{new_text},    undef, 'nothing fixed' );
    is( $result->{fixed_count}, 0,     'fixed_count 0' );
};

subtest 'CRLF lint only does not mention skipped fixes' => sub {
    my $result = run_engine( engine( 'none', 'T001' ), "foo;\r\n" );
    is( $result->{fixes_skipped}, undef, 'no fixes were asked for' );
};

subtest 'fix that dies is a decline' => sub {
    my $result = run_engine( engine( 'safe', qw( T006 T001 ) ), "boom; foo;\n" );
    is( $result->{new_text},    "boom; bar;\n", 'other fixes still applied' );
    is( summary($result),       [ [ 'T006', 1, 1 ] ], 'declined violation reported' );
    is( $result->{fixed_count}, 1,                    'only the applied fix counted' );
};

subtest 'unparseable source' => sub {
    my $real = \&PPI::Document::new;
    no warnings 'redefine';
    local *PPI::Document::new = sub ( $class, @args ) {
        return $real->( $class, @args ) unless ref $args[0] && ${ $args[0] } =~ /broken/;
        $PPI::Document::errstr = 'cannot parse';
        return undef;
    };

    my $result = run_engine( engine( 'none', 'T001' ), "broken;\n" );
    is( $result->{error},      'cannot parse', 'error from PPI' );
    is( $result->{violations}, [],             'no violations' );
    is( $result->{new_text},   undef,          'no new text' );

    package T007 {
        use parent -norequire, 'WordRule';
        sub code       {'T007'}
        sub fix_safety {'safe'}
        sub from       {'foo'}
        sub to         {'broken'}
    }
    $result = run_engine( engine( 'safe', 'T007' ), "foo;\n" );
    is( $result->{error},       'cannot parse', 'fixed text that does not parse is an error' );
    is( $result->{new_text},    undef,          'original kept' );
    is( $result->{fixed_count}, 0,              'nothing fixed' );
    is( summary($result), [ [ 'T007', 1, 1 ] ], 'violations of the original text' );
};

subtest 'builtin_rules_info' => sub {
    is( [ Puff::Engine->builtin_rules_info ],
        [ { code => 'P001', summary => 'suppression comment must list codes' } ], 'P001 listed' );
};

done_testing;
