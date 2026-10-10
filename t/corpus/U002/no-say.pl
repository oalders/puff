print "no feature\n";
{
    use feature 'say';
}
print "outside the block\n";
{
    use 5.008;
    print "old perl\n";
}
{
    use Modern::Perl ();
    print "no import\n";
}
{
    use Moose;
    print "not configured\n";
}
