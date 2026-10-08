use strict;
use warnings;

my @names = ( 'ann', 'bob' ); # expect: B002
my %ages = ( ann => 3 ); # expect: B002
our @ISA;
@ISA = ('Exporter'); # expect: B002
my @empty = (); # expect: B002
my %none = (); # expect: B002
my $ref = [];
@$ref = ( 1, 2 ); # expect: B002
@{$ref} = ( 1, 2 ); # expect: B002
$ref->@* = ( 1, 2 ); # expect: B002
my %h;
%$ref = ( a => 1 ) if 0; # expect: B002
my @x;
@x[ 0, 1 ] = ( 1, 2 ); # expect: B002
@h{ 'a', 'b' } = ( 1, 2 ); # expect: B002
@{$ref}[ 0, 1 ] = ( 1, 2 ); # expect: B002
my @list = map { $_ } ( @names = (1) ); # expect: B002
