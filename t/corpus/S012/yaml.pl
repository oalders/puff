use YAML::XS;
my ( $input, $file );
my $data = Load($input); # expect: S012
$data = LoadFile($file); # expect: S012
$data = YAML::XS::Load($input); # expect: S012
$data = YAML::Load($input); # expect: S012
$data = Load $input; # expect: S012
$data = $obj->Load($input);
$data = Dump($data);
sub safe {
    local $YAML::XS::LoadBlessed = 0;
    return Load($input);
}
sub unsafe { return Load($input) } # expect: S012
