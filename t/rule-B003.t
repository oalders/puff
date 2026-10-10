use v5.36;
use Test2::V0;

use Puff::Engine ();
use Puff::Rules  ();
use Puff::Source ();
use Puff::Test   qw( run_corpus );

run_corpus('B003');

sub lines_with ( $options, $text ) {
    my ($class) = grep { $_->code eq 'B003' } Puff::Rules->load;
    my $rule = $class->new( options => $options );
    my $result
        = Puff::Engine->new( rules => [$rule] )->process_source( Puff::Source->from_string($text), file => 'x.pl' );
    return [ map { $_->line } @{ $result->{violations} } ];
}

my $text = "chmod 0755, \$f;\nmkdir \$d, 0700;\nmy \$x = 010;\n";
is( lines_with( {}, $text ), [3], 'permission modes are skipped by default' );
is( lines_with( { strict => 1 }, $text ), [ 1, 2, 3 ], 'strict reports permission modes too' );
is( lines_with( {}, "my \$x = 09;\n" ), [1], 'invalid octal is still reported' );

# mask values and ->chmod are mode positions too: skipped by default, where
# B010 owns them, and reported under strict like the rest.
my $modes = "\$p->chmod(0755);\nmake_path( \$d, { mask => 0022 } );\n\$p->mkdir( { mode => 0700 } );\n";
is( lines_with( {}, $modes ), [], 'mask and ->chmod modes are skipped by default' );
is( lines_with( { strict => 1 }, $modes ), [ 1, 2, 3 ], 'strict reports mask and ->chmod modes' );

done_testing;
