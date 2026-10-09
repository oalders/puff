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

1;
