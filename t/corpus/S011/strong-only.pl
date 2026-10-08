my ( $token, $sig, $x, $self, $password );
die unless $token eq $x;
die unless $sig eq $self->sigil;
die unless $password eq $x; # expect: S011
die unless $x eq $self->{session_secret}; # expect: S011
my ( $hash, $gen_hash );
die unless $gen_hash eq $hash;
