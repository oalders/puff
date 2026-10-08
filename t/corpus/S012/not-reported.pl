use Storable qw(freeze nstore);
my ( $data, $file, $model );
my $frozen = Storable::freeze($data);
nstore( $data, $file );
my $row = $model->retrieve(1);
my %h = ( thaw => 1 );
$YAML::XS::LoadBlessed = 0;
local $YAML::LoadCode = '';
$Storable::Eval = 0;
