use v5.36;
use Test2::V0;

use PPI          ();
use Puff::Source ();
use Puff::Fix    ();
use Puff::Rule   ();

my @docs;    # PPI drops token locations when a document is destroyed

sub doc_for ($src) {
    my $doc = PPI::Document->new( \( $src->text ) );
    push @docs, $doc;
    $doc->index_locations;
    return $doc;
}

sub word ( $doc, $content ) {
    return $doc->find_first( sub { $_[1]->isa('PPI::Token::Word') && $_[1]->content eq $content } );
}

my $src = Puff::Source->from_string('open(FH, "<$f");');
my $doc = doc_for($src);
my $fh  = word( $doc, 'FH' );

subtest 'Puff::Fix helpers' => sub {
    my $fix = Puff::Fix->new( source => $src );
    ref_is( $fix->source, $src, 'source' );
    $fix->replace( $fh, 'my $fh' );
    is( $fix->edits, [ { start => 5, end => 7, text => 'my $fh' } ], 'replace' );

    $fix = Puff::Fix->new( source => $src );
    $fix->insert_before( $fh, 'X' );
    $fix->insert_after( $fh, 'Y' );
    $fix->delete($fh);
    $fix->replace_range( 1, 2, 'Z' );
    is(
        $fix->edits,
        [
            { start => 5, end => 5, text => 'X' },
            { start => 7, end => 7, text => 'Y' },
            { start => 5, end => 7, text => '' },
            { start => 1, end => 2, text => 'Z' },
        ],
        'insert_before, insert_after, delete, replace_range'
    );
};

subtest 'heredoc declines' => sub {
    my $hsrc    = Puff::Source->from_string("print <<EOT;\nhi\nEOT\nprint 1;\n");
    my $hdoc    = doc_for($hsrc);
    my $stmt    = $hdoc->find_first('PPI::Statement');
    my $heredoc = $hdoc->find_first('PPI::Token::HereDoc');
    my $fix     = Puff::Fix->new( source => $hsrc );
    like( dies { $fix->replace( $stmt, 'x' ) }, qr/heredoc/, 'statement' );
    like( dies { $fix->delete($heredoc) }, qr/heredoc/, 'token itself' );
    like( dies { $fix->insert_before( $stmt, 'x' ) }, qr/heredoc/, 'insert_before' );
    like( dies { $fix->insert_after( $stmt, 'x' ) }, qr/heredoc/, 'insert_after' );
    is( $fix->edits, [], 'nothing recorded' );
    isa_ok( dies { $fix->replace( $stmt, 'x' ) }, 'Puff::Fix::Decline' );
};

subtest 'decline' => sub {
    my $err = dies { Puff::Fix->decline('no way') };
    isa_ok( $err, 'Puff::Fix::Decline' );
    is( $err->message, 'no way', 'message' );
    like( "$err", qr/\Ano way/, 'stringifies to the message' );
};

package My::Rule {
    our @ISA = ('Puff::Rule');
    sub code    {'X001'}
    sub options { { x => 1 } }
}

package My::Fixable {
    our @ISA = ('My::Rule');
    sub fix_safety {'unsafe'}
}

package My::Summary {
    our @ISA = ('My::Rule');
    sub summary {'the summary'}
}

package My::NoFix {
    our @ISA = ('My::Rule');
    sub fix_safety {'none'}
}

subtest 'Puff::Rule' => sub {
    is( My::Rule->new( options => { x => 2 } )->option('x'), 2, 'configured' );
    is( My::Rule->new->option('x'), 1, 'default' );
    like( dies { My::Rule->new->option('y') }, qr/\Arule X001 has no option y\n/, 'undeclared option dies' );

    my $rule = My::Rule->new;
    my $v    = $rule->violation( $fh, message => 'm' );
    isa_ok( $v, 'Puff::Violation' );
    is( $v->code, 'X001', 'code' );
    is( $v->line, 1, 'line' );
    is( $v->column, 6, 'column' );
    is( $v->message, 'm', 'message' );
    is( $v->rule, $rule, 'rule' );
    is( $v->element, $fh, 'element' );
    ok( !$v->fixable, "base fix_safety none: not fixable" );
    is( My::Summary->new->violation($fh)->message, 'the summary', 'message defaults to summary' );
    ok( My::Fixable->new->violation( $fh, message  => "m" )->fixable, "fixable by default when fix_safety declared" );
    ok( !My::Fixable->new->violation( $fh, message => "m", fixable => 0 )->fixable, "explicit 0" );
    ok(
        !My::NoFix->new->violation( $fh, message => 'm', fixable => 1 )->fixable,
        'fix_safety none'
    );

    $v->file('a.pl');
    is( $v->file, 'a.pl', 'file setter' );

    is( [ $rule->check( $fh, $doc ) ], [], 'base check' );
    ok( !$rule->fix( $v, Puff::Fix->new( source => $src ) ), 'base fix' );
    is( $rule->applies_to, 'PPI::Element', 'applies_to default' );
};

done_testing;
