use 5.008;
print "outer off\n";
{
    use feature 'say';
    {
        use 5.008;
        print "inner off\n";
    }
    say "middle on"; # expect: U002
    {
        say "nested on"; # expect: U002
    }
}
print "outer off again\n";
