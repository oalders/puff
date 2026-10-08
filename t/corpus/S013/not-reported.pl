use strict;
use warnings;

use constant TABLE => 'users';

my ( $dbh, $id, $name, $table, @ids, $count );

$dbh->do( 'DELETE FROM users WHERE id = ?', undef, $id );
my $sql = 'SELECT * FROM ' . $dbh->quote_identifier($table) . ' WHERE id = ?';
$sql = 'SELECT * FROM t WHERE name = ' . $dbh->quote($name);
$sql = 'SELECT * FROM ' . TABLE . ' WHERE id = ?';
$sql = 'SELECT * FROM t WHERE id IN (' . join( ',', ('?') x @ids ) . ')';
$sql = 'SELECT * FROM t WHERE id IN (' . join( ',', map { $dbh->quote($_) } @ids ) . ')';
$sql = 'SELECT * FROM t LIMIT ' . int($count);
$sql = "SELECT * FROM t WHERE name = @{[ $dbh->quote($name) ]}";
$sql = sprintf( 'SELECT * FROM t WHERE id = %d LIMIT %d', $id, $count );
$sql = "SELECT * FROM t WHERE id = $id";    ## SQL safe ($id)
$sql = 'SELECT * FROM t WHERE x = ' . helper($id);    ## SQL safe (&helper)
$sql = "SELECT * FROM t WHERE price = '\$5'";
$sql = 'SELECT * FROM t WHERE name = $name';

print "Update $count records in $table\n";
print "Select a $name from the list\n";
die "Delete failed for $id";
my $msg = "update $name";
my $text = "Selected $count items from $table";

my $cache = '';
$cache .= " AND id = $id";

my $doc = <<'SQL';
SELECT * FROM t WHERE name = '$name'
SQL

sub helper { return }
