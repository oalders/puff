package My::OAuth::Verify;
my ( $hash, $gen_hash, $request, $self );
die unless $gen_hash eq $hash; # expect: S011
return $request->signature eq $self->sign($request); # expect: S011
