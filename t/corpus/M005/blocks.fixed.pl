package My::Outer {
    use Moo; # expect: M005
    use namespace::autoclean;

    package My::Outer::Inner {
        use Moose::Role;    # expect: M005
        use namespace::autoclean;
        requires 'name';
    }

    has size => ( is => 'ro' );
}

package My::Done {
    use Mouse;
    use namespace::autoclean;
}

1;
