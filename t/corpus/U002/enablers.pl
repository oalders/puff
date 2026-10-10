{
    use 5.010;
    print "number\n"; # expect: U002
}
{
    use 5.10.0;
    print "dotted\n"; # expect: U002
}
{
    use feature qw( state say );
    print "qw\n"; # expect: U002
}
{
    use feature ':5.10';
    print "bundle\n"; # expect: U002
}
{
    use feature ':all';
    print "all\n"; # expect: U002
}
{
    use Mojo::Base -strict;
    print "mojo\n"; # expect: U002
}
