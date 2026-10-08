use YAML::XS;
my $input;
$YAML::XS::LoadBlessed = 0;
my $data = Load($input);
