use YAML::XS;
my ( $input, $file );
my $data = do { local $YAML::XS::LoadBlessed = 0; Load($input) }; # expect: S012
$data = do { local $YAML::XS::LoadBlessed = 0; LoadFile($file) }; # expect: S012
$data = do { local $YAML::XS::LoadBlessed = 0; YAML::XS::Load($input) }; # expect: S012
$data = do { local $YAML::LoadBlessed = 0; YAML::Load($input) }; # expect: S012
$data = Load $input; # expect: S012
$data = $obj->Load($input);
$data = Dump($data);
sub safe {
    local $YAML::XS::LoadBlessed = 0;
    return Load($input);
}
sub unsafe { return do { local $YAML::XS::LoadBlessed = 0; Load($input) } } # expect: S012
