my ( $file, $ext, @files );
print 'ok' if $file =~ /\.(pl|cgi)$/; # expect: S014
print 'ok' if $file =~ m{\.(?:jpe?g|png)}i; # expect: S014
print 'ok' if $file =~ /\.pm/; # expect: S014
print 'ok' if $file !~ /\.tar\.gz\Z/; # expect: S014
my $re = qr/\Q$ext\E/; # expect: S014
$re = qr/\.\Q$suffix\E$/; # expect: S014
my @pm = grep { /\.pm$/ } @files; # expect: S014
