use Digest::SHA qw(hmac_sha256_hex);
my ( $sig, $expected, $self, $req, $key, $data, $password );
die unless $sig eq $expected; # expect: S011
die if $expected ne $self->{csrf_token}; # expect: S011
die unless $req->param('x') eq $self->signature; # expect: S011
die unless hmac_sha256_hex( $data, $key ) eq $sig; # expect: S011
die unless $self->{'api_secret'} eq $key; # expect: S011
die unless $expected eq $req->header->hmac(); # expect: S011
die unless $password eq $self->password; # expect: S011
