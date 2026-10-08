my ( $path, $root, $self, $file, $base_dir, $docroot );
die 'outside' unless index( $path, $root ) == 0; # expect: S015
die 'outside' unless 0 == index( $file, $self->{root} ); # expect: S015
die 'outside' if index( $path, $base_dir ) != 0; # expect: S015
die 'outside' unless !index( $path, $docroot ); # expect: S015
die 'outside' unless substr( $path, 0, length $root ) eq $root; # expect: S015
die 'outside' unless $path =~ /^\Q$root\E/; # expect: S015
die 'outside' unless $path =~ m{\A\Q$self->{home}\E}; # expect: S015
die 'outside' unless index( $path, $self->root ) == 0; # expect: S015
