my ( $code, $x, $mod ) = ( '1', 'y', 'Foo' );
eval $code; # expect: S004
eval "require $mod; 1"; # expect: S004
eval qq{$x}; # expect: S004
eval("1 + " . $x); # expect: S004
eval; # expect: S004
CORE::eval $code; # expect: S004
my $r = eval "\@{[ 1 ]}" . $x; # expect: S004
eval <<"EOT"; # expect: S004
$x
EOT
eval "1" or die; eval $x; # expect: S004
