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

package My::BeginWith;

use Moose;
BEGIN { with 'My::Builds' }

has begin_with => ( is => 'ro', lazy => 1, builder => '_from_role' );

package My::BeginExtends;

use Moo;
BEGIN { extends('My::Parent'); }

has begin_extends => ( is => 'lazy' );

package My::Parens;

use Moo;
with( 'My::Builds' );

has parens => ( is => 'lazy' );

package My::Parent;

use Moose;
use parent -norequire, 'My::Base';

has parent_builder => ( is => 'ro', lazy => 1, builder => '_from_base' );

package My::Base;

use Moo;
use base 'My::Root';

has base_builder => ( is => 'lazy' );

package My::Qualified;

use Moo;

has qualified => ( is => 'lazy' );

sub My::Qualified::_build_qualified { 1 }

package My::Pkg;

use Moo;

has glob_name => ( is => 'lazy' );

*My::Pkg::_build_glob_name = sub { 1 };

package My::BeginISA;

use Moo;
BEGIN { our @ISA = ('My::Parent') }

has begin_isa => ( is => 'lazy' );

package My::GlobString;

use Moo;

has glob_string => ( is => 'lazy' );

*{"_build_glob_string"} = sub { 1 };

package My::GlobExpr;

use Moo;

has glob_expr => ( is => 'ro', lazy => 1, builder => '_glob_expr' );

{
    no strict 'refs';
    *{ __PACKAGE__ . '::_glob_expr' } = sub { 1 };
}

package My::AddMethodVar;

use Moose;

has added_var => ( is => 'ro', lazy => 1, builder => '_added_var' );

my $method = '_added_var';
__PACKAGE__->meta->add_method( $method => sub { 1 } );

package My::GlobScalar;

use Moo;

has glob_scalar => ( is => 'lazy' );

my $glob_name = '_build_glob_scalar';
*$glob_name = sub { 1 };

package My::GlobSlot;

use Moo;

has glob_slot => ( is => 'lazy' );

*{"_build_glob_slot"}{CODE} = 1;

1;
