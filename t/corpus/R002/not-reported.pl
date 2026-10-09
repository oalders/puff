use v5.36;

package Obj {
    sub new ( $class, @args ) { return bless {}, $class }
    sub map ( $self, @args )  { return @args }
}

my @list = ( 1, 2, 3 );
my %seen;

my @x = map { $_ * 2 } @list;
@x = grep { $_ > 1 } @list;
my $n = grep { $_ > 1 } @list;
$n = () = map { $_ } @list;
print map { $_ } @list;
push @x, grep { $_ } @list;
print scalar grep { $_ } @list;
if ( grep { $_ == 2 } @list ) {
    $n++;
}
grep { $_ == 9 } @list or $n++;
grep( { $_ == 9 } @list ) || $n++;
map( { $_ } @list ), $n++;
my @deep = map { map { $_ + 1 } @list } @list;

sub doubled (@items) {
    map { $_ * 2 } @items;
}

sub evens (@items) {
    return grep { $_ % 2 == 0 } @items;
}

my $code = sub { grep { $_ } @_ };
my @d    = do { map { $_ + 1 } @list };
my @s    = sort { $a <=> $b } map { $_ } @list;
my @g    = grep { map { $_ } @list } @list;

if (@list) {
    map { $_ } @list;
}

my $obj = Obj->new;
$obj->map(@list);
Obj->map(1);
my %h   = ( map => 1, grep => 2 );
my $key = $h{map} + $h{grep};
my $r   = { map { $_ => 1 } @list };
my $ar  = [ map { $_ } @list ];
my $str = 'map { print } @list;';

# map { print } @list;

=pod

grep { $seen{$_}++ } @list;

=cut

print doubled(@list), evens(@list), $code->(@list), @d, @s, @g, @deep, $key, $r, $ar, $str, @x, $n;
