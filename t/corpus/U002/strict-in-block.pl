use feature 'say';
my $name = q{x};
my $ref  = \$name;
{
    use strict;
    ${$ref} = "!";
}
print "x\n"; # expect: U002
