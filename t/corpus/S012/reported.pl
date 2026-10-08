use Storable qw(thaw retrieve);
my ( $data, $file );
my $obj = thaw($data); # expect: S012
$obj = retrieve $file; # expect: S012
$obj = Storable::thaw($data); # expect: S012
$obj = Storable::lock_retrieve($file); # expect: S012
$Storable::Eval = 1; # expect: S012
local $YAML::XS::LoadBlessed = 1; # expect: S012
$YAML::Syck::LoadCode = 'yes'; # expect: S012
