use v5.36;
use Test2::V0;

use Puff::Engine ();
use Puff::Rules  ();
use Puff::Source ();
use Puff::Test   qw( run_corpus );

run_corpus('R002');

my ($class) = grep { $_->code eq 'R002' } Puff::Rules->load;

sub violations ($text) {
    my $result = Puff::Engine->new( rules => [ $class->new ] )
        ->process_source( Puff::Source->from_string($text), file => 'x.pl' );
    return $result->{violations};
}

my $found = violations("map { print } \@x;\ngrep { 1 } \@x;\n");
is(
    [ map { $_->message } @$found ], [ 'map in void context; use a for loop', 'grep in void context; use a for loop' ],
    'message names the function'
);
is( [ map { $_->fixable ? 1 : 0 } @$found ], [ 0, 0 ], 'no fix is offered' );
is( $class->fix_safety, 'none', 'fix safety is none' );

is( scalar @{ violations("sub f { map { print } \@x }\n") }, 0, 'last statement of a sub' );
is( scalar @{ violations("sub f { map { print } \@x; # done\n}\n") }, 0, 'trailing comment is ignored' );
is( scalar @{ violations("sub f { map { print } \@x;\n1 }\n") }, 1, 'not last statement of a sub' );
is( scalar @{ violations("map { print } \@x\n") }, 1, 'last statement of the file' );

done_testing;
