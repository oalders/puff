use v5.36;

# Sibling blocks, loops and subs may reuse a name.
sub one { my $tmp = 1; return $tmp }
sub two { my $tmp = 2; return $tmp }
for my $item ( 1, 2 ) { print $item }
for my $item ( 3, 4 ) { print $item }
if ( my $m = shift ) { print $m }
if ( my $m = shift ) { print $m }

# A declaration after the inner scope does not shadow anything in it.
sub early { my $late = 1; return $late }
my $late = 2;

# Different sigils are different variables.
my @list = ( 1, 2 );
for my $list (@list) { print $list }
{
    my %list = ( a => $list[0] );
    print %list;
}

# The outer variable is not visible inside its own initialiser.
my $value = do { my $value = 1; $value + 1 };

# local is not a declaration.
our $depth = 0;
sub recurse { local $depth = $depth + 1; return $depth }

# An inner our of a name declared with our names the same global.
our $config = 1;
{ our $config; print $config }

# Same scope is B007's business, not this rule's.
my $twice = 1;
my $twice = 2;

# A signature parameter redeclared in the body is in the same scope (B007).
sub f ($p) { my $p = 1; return $p }

# String evals are not parsed.
eval 'my $twice = 3';

# A prototype declares nothing.
our $_;
{
    no feature 'signatures';
    sub topic ($_) { return $_[0] }
}

# A catch variable is not visible after its catch block.
{
    use feature 'try';
    no warnings 'experimental::try';
    try { die } catch ($problem) { print $problem }
    my $problem = 1;
}
