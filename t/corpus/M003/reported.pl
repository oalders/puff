package My::Config;

use Moose;

has path => ( is => 'ro', lazy => 1 ); # expect: M003
has [qw(a b)] => ( is => 'ro', lazy => 1, isa => 'Int' ); # expect: M003
has data => ( is => 'ro', lazy => 1, builder => '_load_data' ); # expect: M003
has 'size', is => 'ro', lazy => '1'; # expect: M003

sub _other { }

__PACKAGE__->meta->make_immutable;

package My::Moo;

use Moo;

has name => ( is => 'lazy' ); # expect: M003
has [qw(c d)] => ( is => 'ro', lazy => 1, builder => 1 ); # expect: M003
has e => ( is => 'ro', lazy => 1 ); # expect: M003
has f => ( is => 'lazy' );

sub _build_f { 1 }
sub _build_c { 1 }
sub _build_d_extra { 1 }

package My::Role {
    use Moose::Role;
    has colour => ( is => 'ro', lazy => 1 ); # expect: M003
}

package My::Child {
    use Mouse;
    extends 'My::Parent';
    has weight => ( is => 'ro', lazy => 1 ); # expect: M003
}

package My::Mentions;

use Moose;

has commented => ( is => 'ro', lazy => 1, builder => '_build_commented' ); # expect: M003
has quoted    => ( is => 'ro', lazy => 1, builder => '_build_quoted' ); # expect: M003
has other     => ( is => 'ro', lazy => 1, builder => '_build_other' ); # expect: M003

# _build_commented is still to do
my $name = '_build_quoted';
my $call = "sub _build_quoted";
around _build_other => sub { 1 };

=pod

sub _build_other { 1 }

=cut

package My::AddOther;

use Moose;

has added_other => ( is => 'ro', lazy => 1, builder => '_added_other' ); # expect: M003

__PACKAGE__->meta->add_method( _something_else => sub { 1 } );

package My::RunTimeRole;

use Moose;

has run_time_role => ( is => 'ro', lazy => 1, builder => '_from_run_time_role' ); # expect: M003

Moose::Util::apply_all_roles( __PACKAGE__, 'My::Builds' );

1;
