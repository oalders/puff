use strict;
use warnings;

my @e = ( q{}, q(), qq{}, qq(), ' ', " ", 'x', "''", '""', '\'' );
my $q = q{''};
print <<'EOT';
''
EOT
# ''
