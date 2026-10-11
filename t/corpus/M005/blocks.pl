package My::Outer {
    use Moo; # expect: M005

    package My::Outer::Inner {
        use Moose::Role;    # expect: M005
        requires 'name';
    }

    has size => ( is => 'ro' );
}

package My::Done {
    use Mouse;
    use namespace::autoclean;
}

1;
