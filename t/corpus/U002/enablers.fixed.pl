{
    use 5.010;
    say "number"; # expect: U002
}
{
    use 5.10.0;
    say "dotted"; # expect: U002
}
{
    use feature qw( state say );
    say "qw"; # expect: U002
}
{
    use feature ':5.10';
    say "bundle"; # expect: U002
}
{
    use feature ':all';
    say "all"; # expect: U002
}
{
    use Mojo::Base -strict;
    say "mojo"; # expect: U002
}
