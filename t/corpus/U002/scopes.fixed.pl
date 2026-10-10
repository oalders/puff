print "before use\n";
use feature 'say';
say "feature"; # expect: U002
{
    use 5.008;
    print "turned off\n";
}
say "back on"; # expect: U002
sub foo {
    use Modern::Perl;
    say "module"; # expect: U002
}
