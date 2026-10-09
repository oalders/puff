use v5.36;
use Test2::V0;

use Puff::Engine ();
use Puff::Rules  ();
use Puff::Source ();
use Puff::Test   qw( run_corpus );

run_corpus('B006');

sub engine ( $options, %args ) {
    my ($class) = grep { $_->code eq 'B006' } Puff::Rules->load;
    return Puff::Engine->new( rules => [ $class->new( options => $options ) ], %args );
}

sub lines_with ( $options, $text ) {
    my $result = engine($options)->process_source( Puff::Source->from_string($text), file => 'x.pl' );
    return [ map { $_->line } @{ $result->{violations} } ];
}

sub fixed ($text) {
    my $result = engine( {}, fix_mode => 'unsafe' )->process_source( Puff::Source->from_string($text), file => 'x.pl' );
    return $result->{new_text};
}

my $args = "sub f {\n    my ( \$self, \$c ) = \@_;\n    my \$x = shift;\n    return;\n}\n";
is( lines_with( {}, $args ), [], 'subroutine arguments are allowed by default' );
is(
    lines_with( { 'allow-unused-subroutine-arguments' => 0 }, $args ), [ 2, 2, 3 ],
    'and reported when the option is off'
);

my $guard = "sub f {\n    my \$g = make_guard();\n    return;\n}\n";
is( lines_with( {}, $guard ), [2], 'an unlisted function is reported' );
is( lines_with( { 'allow-if-computed-by' => ['make_guard'] }, $guard ), [], 'allow-if-computed-by' );

is(
    fixed("sub f {\n    my \$x;\n    return 1;\n}\n"), "sub f {\n    return 1;\n}\n",
    'a declaration alone on its line is removed with the line'
);
is( fixed("sub f { my \$x; return 1 }\n"), "sub f {  return 1 }\n", 'a declaration sharing its line is removed alone' );

done_testing;
