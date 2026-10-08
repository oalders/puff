use v5.36;

package My::Block {
    use Moose; # expect: M001
    has x => ( is => 'ro' );
}

package My::BlockDone {
    use Moose;
    has x => ( is => 'ro' );
    __PACKAGE__->meta()->make_immutable( inline_constructor => 0 );
}

package My::BlockTrue {
    use Mouse; # expect: M001
    has x => ( is => 'ro' );
    __PACKAGE__->meta->make_immutable;

    1;
}

1;
