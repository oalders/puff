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

for my $n (@list) {
    map { print } $n; # expect: R002
}

foreach (@list) {
    grep { $seen{$_}++ } $_; # expect: R002
}

while ( !$y ) {
    grep { $seen{$_}++ } @list; # expect: R002
}

until ($y) {
    map { print } @list; # expect: R002
}

for ( my $i = 0; $i < 1; $i++ ) {
    map { print } @list; # expect: R002
}

for my $n (@list) {
    print $n;
}
continue {
    map { print } @list; # expect: R002
}

map { 1 } @list until $y; # expect: R002

map { print } @list # expect: R002
    if $y;

map { # expect: R002
    print <<~"EOT";
        item $_
        EOT
} @list;

grep /re/, @list; # expect: R002
map lc, @list; # expect: R002

my $v = do {
    map { print } @list; # expect: R002
    1;
};

if ($y) {
    map { print } @list; # expect: R002
    $y++;
}

map { print } @list ? 1 : 2; # expect: R002

sub each_row (@rows) {
    map { print } @$_ for @rows; # expect: R002
}

sub each_list (@lists) {
    for my $n (@lists) {
        map { print } @$n; # expect: R002
    }
}

show( @nested, $v );
each_row( [@list] );
each_list( [@list] );

map { print } @list; # expect: R002
