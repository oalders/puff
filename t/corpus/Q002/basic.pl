use strict;
use warnings;

my %h = ( 'name' => 1, "age" => 2, q{city} => 3 ); # expect: Q002 Q002 Q002
my $r = { 'with_underscore' => 1, '_lead' => 2 }; # expect: Q002 Q002
print $h{'name'}, $h{"age"}, $r->{'_lead'}, "\n"; # expect: Q002 Q002 Q002
print $h{ 'name' }, $r->{'_lead'}{'with_underscore'}, "\n"; # expect: Q002 Q002 Q002
my @one = @h{'name'}; # expect: Q002
my %opts = (
    'verbose' # expect: Q002
        => 1,
    'shift' => 2, # expect: Q002
);
print $opts{'shift'}; # expect: Q002
