my ( $path, $root, $self, $file, $base_dir, $docroot );
die 'outside' unless $path =~ m{\A\Q$root\E(?:/|\z|(?<=/))}; # expect: S015
die 'outside' unless $file =~ m{\A\Q$self->{root}\E(?:/|\z|(?<=/))}; # expect: S015
die 'outside' if $path !~ m{\A\Q$base_dir\E(?:/|\z|(?<=/))}; # expect: S015
die 'outside' unless $path =~ m{\A\Q$docroot\E(?:/|\z|(?<=/))}; # expect: S015
die 'outside' unless substr( $path, 0, length $root ) eq $root; # expect: S015
die 'outside' unless $path =~ /^\Q$root\E(?:\/|\z|(?<=\/))/; # expect: S015
die 'outside' unless $path =~ m{\A\Q$self->{home}\E(?:/|\z|(?<=/))}; # expect: S015
die 'outside' unless index( $path, $self->root ) == 0; # expect: S015
