use v5.36;
use Test2::V0;

use Puff::Engine    ();
use Puff::Source    ();
use Puff::Violation ();

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
    sub code                            {'T006'}
    sub fix_safety                      {'safe'}
    sub from                            {'boom'}
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
    is(
        summary($result), [ [ 'T002', 1, 1 ], [ 'T001', 1, 6 ], [ 'P001', 3, 1 ], [ 'T001', 4, 1 ] ],
        'sorted by line and column, suppressed dropped, P001 included'
    );
    is( [ map { $_->file } @{ $result->{violations} } ], [ ('x.pl') x 4 ], 'file set' );
    my ($p001) = grep { $_->code eq 'P001' } @{ $result->{violations} };
    is( $p001->fixable, 0, 'P001 is not fixable' );
    is( $p001->message, 'suppression comment must list codes', 'P001 message' );
    is( $result->{new_text}, undef, 'no new text' );
    is( $result->{fixed_count}, 0, 'nothing fixed' );
    is( $result->{error}, undef, 'no error' );
    is( $result->{fixes_skipped}, undef, 'fixes not skipped' );
};

subtest 'P001 cannot be suppressed' => sub {
    my $result = run_engine( engine( 'none', 'T001' ), "# puff: ignore-file P001\n# puff: ignore\n" );
    is( summary($result), [ [ 'P001', 2, 1 ] ], 'P001 still reported' );
};

subtest 'safe mode' => sub {
    my $result = run_engine( engine( 'safe', qw( T001 T002 ) ), "foo; baz;\nfoo;\n" );
    is( $result->{new_text}, "bar; baz;\nbar;\n", 'T001 fixed, T002 left' );
    is( summary($result), [ [ 'T002', 1, 6 ] ], 'T002 still reported' );
    is( $result->{fixed_count}, 2, 'two fixed' );
    is( $result->{error}, undef, 'no error' );
};

subtest 'unsafe mode' => sub {
    my $result = run_engine( engine( 'unsafe', qw( T001 T002 ) ), "foo; baz;\n" );
    is( $result->{new_text}, "bar; qux;\n", 'both fixed' );
    is( summary($result), [], 'nothing left' );
    is( $result->{fixed_count}, 2, 'two fixed' );
};

subtest 'nothing fixable leaves new_text undef' => sub {
    my $result = run_engine( engine( 'safe', 'T002' ), "baz;\n" );
    is( $result->{new_text}, undef, 'unchanged' );
    is( $result->{fixed_count}, 0, 'nothing fixed' );
    is( summary($result), [ [ 'T002', 1, 1 ] ], 'still reported' );
};

subtest 'fix loop' => sub {
    my $result = run_engine( engine( 'safe', qw( T003 T004 ) ), "foo;\n" );
    is( $result->{new_text}, "done;\n", 'second pass fixed what the first produced' );
    is( summary($result), [], 'nothing left' );
    is( $result->{fixed_count}, 1, 'original count minus remaining' );
};

subtest 'pass cap' => sub {
    my $result = run_engine( engine( 'safe', 'T005' ), "a;\n" );
    is( $result->{error}, 'fix loop did not converge', 'error' );
    is( $result->{new_text}, undef, 'original kept' );
    is( $result->{fixed_count}, 0, 'nothing fixed' );
    is( summary($result), [ [ 'T005', 1, 1 ] ], 'violations of the original text' );
};

subtest 'CRLF' => sub {
    my $result = run_engine( engine( 'unsafe', 'T001' ), "foo;\r\nfoo;\r\n" );
    is( summary($result), [ [ 'T001', 1, 1 ], [ 'T001', 2, 1 ] ], 'violations reported' );
    like( $result->{fixes_skipped}, qr/CR/, 'fixes_skipped set' );
    is( $result->{new_text}, undef, 'nothing fixed' );
    is( $result->{fixed_count}, 0, 'fixed_count 0' );
    is( [ map { $_->fixable } @{ $result->{violations} } ], [ 0, 0 ], 'violations not offered as fixable' );
};

subtest 'lone CR' => sub {
    my $result = run_engine( engine( 'unsafe', 'T001' ), "foo;\rfoo;\n" );
    like( $result->{fixes_skipped}, qr/CR/, 'fixes_skipped set' );
    is( $result->{new_text}, undef, 'nothing fixed' );
    is(
        [ map { $_->fixable } @{ $result->{violations} } ], [ (0) x @{ $result->{violations} } ],
        'violations not offered as fixable'
    );
};

subtest 'CRLF lint only does not mention skipped fixes' => sub {
    my $result = run_engine( engine( 'none', 'T001' ), "foo;\r\n" );
    is( $result->{fixes_skipped}, undef, 'no fixes were asked for' );
    is( $result->{violations}[0]->fixable, 0, 'not offered as fixable' );
};

subtest 'fix that dies is an error' => sub {
    my $result = run_engine( engine( 'safe', qw( T006 T001 ) ), "boom; foo;\n" );
    is( $result->{error}, 'rule T006 fix failed: nope', 'error names the rule' );
    is( $result->{new_text}, undef, 'file left unfixed' );
    is( $result->{fixed_count}, 0, 'nothing fixed' );
    is( summary($result), [ [ 'T006', 1, 1 ], [ 'T001', 1, 7 ] ], 'violations of the original text' );
};

package T010 {    # fix declines with Puff::Fix->decline
    use v5.36;
    use parent -norequire, 'WordRule';
    sub code                            {'T010'}
    sub fix_safety                      {'safe'}
    sub from                            {'nah'}
    sub fix ( $self, $violation, $fix ) { Puff::Fix->decline('not today') }
}

package T011 {    # fix touches a heredoc, which declines
    use v5.36;
    use parent -norequire, 'WordRule';
    sub code       {'T011'}
    sub fix_safety {'safe'}
    sub applies_to {'PPI::Statement'}

    sub check ( $self, $elem, $doc ) {
        return unless $elem->find_first('PPI::Token::HereDoc');
        return $self->violation( $elem, message => 'heredoc' );
    }

    sub fix ( $self, $violation, $fix ) {
        $fix->replace( $violation->element, 'x;' );
        return 1;
    }
}

package main;

subtest 'Puff::Fix->decline is a silent decline' => sub {
    my $result = run_engine( engine( 'safe', qw( T010 T001 ) ), "nah; foo;\n" );
    is( $result->{error}, undef, 'no error' );
    is( $result->{new_text}, "nah; bar;\n", 'other fixes still applied' );
    is( summary($result), [ [ 'T010', 1, 1 ] ], 'declined violation reported' );
    is( $result->{fixed_count}, 1, 'only the applied fix counted' );

    $result = run_engine( engine( 'safe', 'T011' ), "print <<EOT;\nhi\nEOT\n" );
    is( $result->{error}, undef, 'heredoc guard declines without an error' );
    is( $result->{new_text}, undef, 'nothing changed' );
};

package T012 {    # one fix whose own edits overlap
    use v5.36;
    use parent -norequire, 'WordRule';
    sub code       {'T012'}
    sub fix_safety {'safe'}
    sub from       {'foo'}

    sub fix ( $self, $violation, $fix ) {
        my $start = $fix->source->start_of( $violation->element );
        $fix->replace_range( $start, $start + 2, 'AB' );
        $fix->replace_range( $start + 1, $start + 3, 'CD' );
        return 1;
    }
}

package T013 {    # check returns something that is not a violation
    use v5.36;
    use parent -norequire, 'WordRule';
    sub code                         {'T013'}
    sub check ( $self, $elem, $doc ) { return 'oops' }
}

package main;

subtest 'a fix whose own edits overlap is not applied' => sub {
    my $result = run_engine( engine( 'safe', 'T012' ), "foo;\n" );
    is( $result->{error}, undef, 'no error' );
    is( $result->{new_text}, undef, 'text unchanged' );
    is( summary($result), [ [ 'T012', 1, 1 ] ], 'still reported' );
};

subtest 'check returning a non-violation' => sub {
    my $result = run_engine( engine( 'none', qw( T013 T001 ) ), "foo;\n" );
    is( $result->{error}, 'rule T013 failed: check returned a non-violation', 'error names the rule' );
    is( summary($result), [ [ 'T001', 1, 1 ] ], 'other rules still report' );
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
    is( $result->{error}, 'cannot parse', 'error from PPI' );
    is( $result->{violations}, [], 'no violations' );
    is( $result->{new_text}, undef, 'no new text' );

    package T007 {
        use parent -norequire, 'WordRule';
        sub code       {'T007'}
        sub fix_safety {'safe'}
        sub from       {'foo'}
        sub to         {'broken'}
    }
    $result = run_engine( engine( 'safe', 'T007' ), "foo;\n" );
    is( $result->{error}, 'cannot parse', 'fixed text that does not parse is an error' );
    is( $result->{new_text}, undef, 'original kept' );
    is( $result->{fixed_count}, 0, 'nothing fixed' );
    is( summary($result), [ [ 'T007', 1, 1 ] ], 'violations of the original text' );
};

package T008 {    # check dies
    use v5.36;
    use parent -norequire, 'WordRule';
    sub code                         {'T008'}
    sub check ( $self, $elem, $doc ) { die "kaboom\n" }
}

package T009 {    # check dies only on what T001 produces
    use v5.36;
    use parent -norequire, 'WordRule';
    sub code {'T009'}

    sub check ( $self, $elem, $doc ) {
        die "saw bar\n" if $elem->content eq 'bar';
        return;
    }
}

package main;

subtest 'rule whose check dies' => sub {
    my $result = run_engine( engine( 'none', qw( T008 T001 ) ), "foo;\n" );
    is( $result->{error}, 'rule T008 failed: kaboom', 'error names the rule' );
    is( summary($result), [ [ 'T001', 1, 1 ] ], 'other rules still report' );

    $result = run_engine( engine( 'safe', qw( T008 T001 ) ), "foo;\n" );
    is( $result->{new_text}, undef, 'no fixes on a partial lint' );
    is( $result->{fixed_count}, 0, 'nothing fixed' );
};

subtest 'rule whose check dies on the fixed text' => sub {
    my $result = run_engine( engine( 'safe', qw( T009 T001 ) ), "foo;\n" );
    is( $result->{error}, 'rule T009 failed: saw bar', 'error set' );
    is( $result->{new_text}, undef, 'original kept' );
    is( $result->{fixed_count}, 0, 'nothing fixed' );
    is( summary($result), [ [ 'T001', 1, 1 ] ], 'violations of the original lint' );
};

subtest 'S002 and S003 fix the same open' => sub {
    require Puff::Rule::Security::TwoArgOpen;
    require Puff::Rule::Security::BarewordFilehandle;
    my $engine = engine( 'unsafe', qw( Puff::Rule::Security::TwoArgOpen Puff::Rule::Security::BarewordFilehandle ) );
    my $result = run_engine( $engine, qq{open(FH, "<\$f"); my \@l = <FH>; close FH;\n} );
    is( $result->{error}, undef, 'no error' );
    is( $result->{new_text}, qq{open(my \$fh, '<', \$f); my \@l = <\$fh>; close \$fh;\n}, 'both fixes applied' );
    is( summary($result), [], 'nothing left' );
    is( $result->{fixed_count}, 2, 'two fixed' );
};

package T014 {    # unsafe rule whose "safe" violations are safe
    use v5.36;
    use parent -norequire, 'WordRule';
    sub code       {'T014'}
    sub fix_safety {'unsafe'}
    sub from       {'safe'}
    sub to         {'fixed'}

    sub check ( $self, $elem, $doc ) {
        my $word = $elem->content;
        return unless $word eq 'safe' || $word eq 'risky';
        return $self->violation( $elem, fix_safety => $word eq 'safe' ? 'safe' : 'unsafe' );
    }

    sub fix ( $self, $violation, $fix ) {
        $fix->replace( $violation->element, 'fixed' );
        return 1;
    }
}

package T015 {    # passes a fix_safety that is not safe or unsafe
    use v5.36;
    use parent -norequire, 'WordRule';
    sub code                         {'T015'}
    sub fix_safety                   {'unsafe'}
    sub check ( $self, $elem, $doc ) { return $self->violation( $elem, fix_safety => 'none' ) }
}

package main;

subtest 'per-violation fix safety' => sub {
    my $result = run_engine( engine( 'safe', 'T014' ), "safe; risky;\n" );
    is( $result->{new_text}, "fixed; risky;\n", 'only the safe violation is fixed in safe mode' );
    is( [ map { $_->fix_safety } @{ $result->{violations} } ], ['unsafe'], 'the unsafe one remains' );

    $result = run_engine( engine( 'unsafe', 'T014' ), "safe; risky;\n" );
    is( $result->{new_text}, "fixed; fixed;\n", 'both are fixed in unsafe mode' );

    $result = run_engine( engine( 'none', 'T015' ), "x;\n" );
    like( $result->{error}, qr/rule T015 failed: rule T015 gave fix_safety 'none'/, 'bad fix_safety dies' );
};

package T016 {    # a rule-paths style rule: no per-violation fix_safety
    use v5.36;
    use parent -norequire, 'WordRule';
    sub code       {'T016'}
    sub fix_safety {'unsafe'}
    sub from       {'plain'}
    sub to         {'done'}
}

package T017 {    # builds a violation with a fix_safety that is not safe or unsafe
    use v5.36;
    use parent -norequire, 'WordRule';
    sub code       {'T017'}
    sub fix_safety {'safe'}
    sub from       {'odd'}
    sub to         {'done'}

    # Rule::violation dies on a bad fix_safety, so build it directly.
    sub check ( $self, $elem, $doc ) {
        return unless $elem->content eq $self->from;
        return Puff::Violation->new(
            rule       => $self,
            code       => $self->code,
            element    => $elem,
            line       => $elem->location->[0],
            column     => $elem->location->[1],
            message    => 'odd',
            fixable    => 1,
            fix_safety => 'bogus',
        );
    }
}

package T018 {    # a rule with no fix whose violation claims a safe fix
    use v5.36;
    use parent -norequire, 'WordRule';
    sub code       {'T018'}
    sub fix_safety {'none'}
    sub from       {'odd'}
    sub to         {'done'}

    # Rule::violation clears fixable for a none rule, so build it directly.
    sub check ( $self, $elem, $doc ) {
        return unless $elem->content eq $self->from;
        return Puff::Violation->new(
            rule       => $self,
            code       => $self->code,
            element    => $elem,
            line       => $elem->location->[0],
            column     => $elem->location->[1],
            message    => 'odd',
            fixable    => 1,
            fix_safety => 'safe',
        );
    }
}

package main;

subtest 'a violation without its own safety uses the rule\'s' => sub {
    my $result = run_engine( engine( 'safe', 'T016' ), "plain;\n" );
    is( $result->{new_text}, undef, 'unsafe rule is not fixed in safe mode' );
    is( summary($result), [ [ 'T016', 1, 1 ] ], 'still reported in safe mode' );
    is( [ map { $_->fix_safety } @{ $result->{violations} } ], ['unsafe'], 'violation reports the rule\'s safety' );

    $result = run_engine( engine( 'unsafe', 'T016' ), "plain;\n" );
    is( $result->{new_text}, "done;\n", 'fixed in unsafe mode' );
};

subtest 'an unknown fix_safety is never fixed' => sub {
    for my $mode (qw( safe unsafe )) {
        my $result = run_engine( engine( $mode, 'T017' ), "odd;\n" );
        is( $result->{new_text}, undef, "not fixed in $mode mode" );
        is( summary($result), [ [ 'T017', 1, 1 ] ], "still reported in $mode mode" );
        is(
            [ map { $_->fix_safety } @{ $result->{violations} } ], ['bogus'],
            "fix_safety is still bogus in $mode mode"
        );
    }
};

subtest 'a rule with fix_safety none is never fixed' => sub {
    for my $mode (qw( safe unsafe )) {
        my $result = run_engine( engine( $mode, 'T018' ), "odd;\n" );
        is( $result->{error}, undef, "no error in $mode mode" );
        is( $result->{new_text}, undef, "not fixed in $mode mode" );
        is( summary($result), [ [ 'T018', 1, 1 ] ], "still reported in $mode mode" );
    }
};

subtest 'builtin_rules_info' => sub {
    is(
        [ Puff::Engine->builtin_rules_info ],
        [ { code => 'P001', summary => 'suppression comment must list codes' } ], 'P001 listed'
    );
};

done_testing;
