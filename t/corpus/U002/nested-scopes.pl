use 5.008;
print "outer off\n";
{
    use feature 'say';
    {
        use 5.008;
        print "inner off\n";
    }
    print "middle on\n"; # expect: U002
    {
        print "nested on\n"; # expect: U002
    }
}
print "outer off again\n";
