use strict;
use warnings;

my @rows = ( [ 1, 2 ] );
my %ages = ( ann => 3 );
my $aref = [ 1, 2 ];
my $href = { a => 1 };
my @copy = @{$aref};
$aref->[0] = [ 1, 2 ];
$href->{a} = { b => 1 };
my %h;
$h{a} = [ 1, 2 ];
$h{a}{b} = { c => 1 };
my @x;
$x[0] = [ 1, 2 ];
${$aref}[0] = [1];
$$aref[0] = [1];
my @list = ( 1, 2 );
@list = qw( a b );
@list = sort @list;
our @ISA = 'Exporter';
my $count = () = ( 1, 2 );

# An array of rows whose first row is a header: the arrayref is meant
# (Dist::Zilla's generated t/00-report-prereqs.t).
my @reports = [qw/Module Want Have/];
push @reports, [ 'Foo', 1, 2 ];

# A one-element slice assigns the reference to that element.
my @lines;
my $n = 0;
@lines[ $n++ ] = [split];
