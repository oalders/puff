print "before use\n";
use feature 'say';
print "feature\n"; # expect: U002
{
    use 5.008;
    print "turned off\n";
}
print "back on\n"; # expect: U002
sub foo {
    use Modern::Perl;
    print "module\n"; # expect: U002
}
