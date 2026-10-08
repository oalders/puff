my ( $file, $ext, @files );
print 'ok' if $file =~ /\.(pl|cgi)\z/; # expect: S014
print 'ok' if $file =~ m{\.(?:jpe?g|png)\z}i; # expect: S014
print 'ok' if $file =~ /\.pm\z/; # expect: S014
print 'ok' if $file !~ /\.tar\.gz\z/; # expect: S014
my $re = qr/\Q$ext\E\z/; # expect: S014
$re = qr/\.\Q$suffix\E\z/; # expect: S014
my @pm = grep { /\.pm\z/ } @files; # expect: S014
