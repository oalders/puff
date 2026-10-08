use strict;
use warnings;

my @e = ( q{}, q(), qq{}, qq(), ' ', " ", 'x', "''", '""', '\'' );
my $q = q{''};
print <<'EOT';
''
EOT
# ''
my %h;
my $r = {};
print $h{''}, $h{ "" }, $r->{''}, @h{''};
