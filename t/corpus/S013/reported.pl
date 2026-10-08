use strict;
use warnings;

my ( $dbh, $id, $name, $table, %args, $obj, @ids );

$dbh->do("DELETE FROM users WHERE id = $id");    # expect: S013
my $sql = "SELECT * FROM users WHERE name = '$name'";    # expect: S013
$sql = 'SELECT * FROM ' . $table . ' WHERE id = ?';    # expect: S013
$sql = "select name from users where id = $args{id}";    # expect: S013
$sql = "UPDATE users SET name = '$obj->{name}' WHERE id = ?";    # expect: S013
$sql = 'INSERT INTO log (msg) VALUES (' . build_values($name) . ')';    # expect: S013
$sql = 'SELECT * FROM t WHERE id = ' . $obj->id;    # expect: S013
$sql = "SELECT * FROM t WHERE id IN (@ids)";    # expect: S013
$sql = "SELECT * FROM t WHERE id = @{[ $obj->id ]}";    # expect: S013
$sql = 'DROP TABLE ' . My::DB->table_name;    # expect: S013
$sql = sprintf( 'SELECT * FROM %s WHERE id = %d', $table, $id );    # expect: S013

my $query = 'SELECT * FROM users';
$query .= " WHERE name = '$name'";    # expect: S013
my $where_sql = '';
$where_sql .= " AND id = $id";    # expect: S013

my $sth = $dbh->prepare(<<"END");    # expect: S013
SELECT *
  FROM users
 WHERE name = '$name'
END

$sth = $dbh->prepare(<<SQL);    # expect: S013
  WHERE name = '$name'
SQL

$sql = "SELECT * FROM t WHERE a = $id AND b = $name"; ## SQL safe ($id)    # expect: S013

sub build_values { return }
