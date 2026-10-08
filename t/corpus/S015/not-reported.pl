my ( $path, $root, $name, $line, $prefix );
die 'outside' unless $path =~ m{\A\Q$root\E(?:/|\z)};
die 'outside' unless $path =~ m{^\Q$root\E/};
print 'found' if index( $line, $name ) == 0;
print 'found' if index( $path, $root ) > 5;
print 'found' if index( $path, $root ) >= 0;
$path =~ s/^\Q$root\E//;
print 'found' if $line =~ /^\Q$name\E/;
print "x" if index( $msg, $prefix ) == 0;
