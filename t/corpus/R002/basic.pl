use v5.36;

my @list = ( 1, 2, 3 );
my %seen;
my $y = 1;

map { print } @list; # expect: R002
grep { $seen{$_}++ } @list; # expect: R002
map print, @list; # expect: R002
map( { print } @list ); # expect: R002
grep( $seen{$_}++, @list ); # expect: R002
map { print } @list if $y; # expect: R002
grep { $seen{$_}++ } @list unless $y; # expect: R002
map { print } @$_ for [@list]; # expect: R002
map { print } @list if $y or !@list; # expect: R002
CORE::map { print } @list; # expect: R002
map { $_ => 1 } @list; # expect: R002
map +{ a => $_ }, @list; # expect: R002

LOOP: map { print } @list; # expect: R002

sub show (@items) {
    map { print } @items; # expect: R002
    return scalar @items;
}

for my $n (@list) {
    grep { $seen{$_}++ } $n; # expect: R002
    next;
}

my @nested = map {
    grep { $seen{$_}++ } @list; # expect: R002
    $_ * 2;
} @list;

show(@nested);

map { print } @list; # expect: R002
