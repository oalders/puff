use v5.36;
use Test2::V0;

use Puff::Engine ();
use Puff::Rules  ();
use Puff::Source ();
use Puff::Test qw( run_corpus );

run_corpus('S007');

sub lines_with ( $options, $text ) {
    my ($class) = grep { $_->code eq 'S007' } Puff::Rules->load;
    my $rule    = $class->new( options => $options );
    my $result  = Puff::Engine->new( rules => [$rule] )->process_source( Puff::Source->from_string($text), file => 'x.pl' );
    return [ map { $_->line } @{ $result->{violations} } ];
}

my $text = "my \$x = '/scratch/a';\nmy \$y = '/tmp/a';\n";
is( lines_with( {}, $text ), [2], 'default directories' );
is( lines_with( { 'tmp-directories' => ['/scratch/'] }, $text ), [1], 'tmp-directories replaces the list' );
is( lines_with( { 'tmp-directories' => [] }, $text ), [], 'an empty list turns the string check off' );
like(
    dies { lines_with( { 'tmp-directories' => ['tmp'] }, "1;\n" ) },
    qr/tmp-directories must be a list of absolute paths/, 'a relative path is rejected'
);

done_testing;
