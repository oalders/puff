package My::Config;

use Moose;

has path    => ( is => 'ro', lazy => 1, default => '/etc' );
has data    => ( is => 'ro', lazy => 1, builder => '_build_data' );
has auto    => ( is => 'ro', lazy_build => 1 );
has eager   => ( is => 'ro', lazy => 0 );
has maybe   => ( is => 'ro', lazy => $lazy );
has code    => ( is => 'ro', lazy => 1, builder => sub { 1 } );
has numeric => ( is => 'ro', lazy => 1, builder => 1 );
has '+base' => ( lazy => 1 );
has opts    => ( is => 'ro', lazy => 1, %rest );
has 'wrap'  => ( is => 'lazy' );
has glob    => ( is => 'ro', lazy => 1, builder => '_glob' );
has meta    => ( is => 'ro', lazy => 1, builder => '_added' );

sub _build_data { [] }
*_glob = sub { 1 };
__PACKAGE__->meta->add_method( _added => sub { 1 } );

package My::Moo;

use Moo;

has name => ( is => 'lazy' );
has age  => ( is => 'lazy', default => 3 );
has c    => ( is => 'ro', lazy => 1, builder => 1 );

sub _build_name { 'x' }
sub _build_c    { 1 }

package My::Child;

use Moo;
extends 'My::Parent';

has inherited => ( is => 'lazy' );
has named     => ( is => 'ro', lazy => 1, builder => '_from_parent' );

package My::WithRole;

use Moose;
with 'My::Builds';

has from_role => ( is => 'ro', lazy => 1, builder => '_from_role' );

package My::Role;

use Moo::Role;

has required_builder => ( is => 'lazy' );

package My::ISA;

use Moo;
our @ISA = ('My::Parent');

has isa_builder => ( is => 'lazy' );

package My::Plain;

has nothing => ( is => 'ro', lazy => 1 );

1;
