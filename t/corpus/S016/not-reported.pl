my ( $x, $obj );
require Foo::Bar;
require 5.010;
require v5.36;
require 'config.pl';
require( $] >= 5.010 ? 'mro.pm' : 'MRO/Compat.pm' );
my $r = do { 1 + 2 };
do 'local.pl';
$obj->require($x);
$obj->do($x);

sub load ($module) {
    die "bad module name\n" unless $module =~ /\A\w+(?:::\w+)*\z/;
    ( my $file = "$module.pm" ) =~ s{::}{/}g;
    require $file;
}
