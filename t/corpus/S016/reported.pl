my ( $file, $class, $repo, $name, $config );
require $file; # expect: S016
eval { require $file; 1 } or die; # expect: S016
require "$class.pm"; # expect: S016
require( "Plugin/" . $name . '.pm' ); # expect: S016
my $conf = do "$repo/.env.pl"; # expect: S016
$conf = do $config or die; # expect: S016
