use v5.36;
use Test2::V0;

use Path::Tiny qw( tempdir );

use lib 't/lib';
use Puff::Engine ();
use Puff::Rules  ();
use Puff::Source ();
use TestCommand  qw( run_capture );

# Every string over a small alphabet that ends in `\n`, as `print "...";`.
# Where U002 fixes one, the `say` it becomes must compile and print the
# same bytes. One perl process compiles and runs each statement on its own
# (a string eval compiles as perl -c does), without strict and with $\
# unset, and prints its output in hex, or `error` if it does not compile.

my @alphabet = ( 'a', '$', '@', '\\', 'n', '{', '}', q{ } );
my @bodies   = (q{});
my @level    = (q{});
for ( 1 .. 4 ) {
    @level = map {
        my $s = $_;
        map { $s . $_ } @alphabet
    } @level;
    push @bodies, @level;
}
my @lines = map {qq{print "$_\\n";}} @bodies;

# Fixing is slow on files with many prints, so the lines go in small batches.
my ($class) = grep { $_->code eq 'U002' } Puff::Rules->load;
my $engine = Puff::Engine->new( rules => [ $class->new ], fix_mode => 'unsafe' );
my @fixed;
for ( my $i = 0 ; $i < @lines ; $i += 25 ) {
    my @batch  = @lines[ $i .. ( $i + 24 < $#lines ? $i + 24 : $#lines ) ];
    my $text   = join "\n", q{use feature 'say';}, @batch, q{};
    my $result = $engine->process_source( Puff::Source->from_string($text), file => 'x.pl' );
    die $result->{error} if $result->{error};
    my @got = split /\n/, $result->{new_text} // $text;
    shift @got;
    die "batch at $i lost lines" unless @got == @batch;
    push @fixed, @got;
}

my $DRIVER = <<'END';
while ( my $code = <> ) {
    chomp $code;
    my $sub = eval "no strict; no warnings; use feature 'say'; sub { $code }";
    if ( !$sub ) { print "error\n"; next }
    open my $fh, '>', \my $buf or die $!;
    my $old = select $fh;
    local $\;
    $sub->();
    select $old;
    close $fh;
    print unpack( 'H*', $buf ), "\n";
}
END

my @pairs = grep { $fixed[$_] ne $lines[$_] } 0 .. $#lines;
ok( @pairs > 100, 'fixes are offered (' . @pairs . ')' );

my $dir = tempdir();
$dir->child('driver.pl')->spew_utf8($DRIVER);
$dir->child('input')->spew_utf8( map {"$lines[$_]\n$fixed[$_]\n"} @pairs );
my @out = split /\n/, run_capture( $dir->child('stderr'), $^X, $dir->child('driver.pl'), $dir->child('input') );
is( scalar @out, 2 * @pairs, 'one result per statement' );

for my $i ( 0 .. $#pairs ) {
    my ( $want, $got ) = @out[ 2 * $i, 2 * $i + 1 ];
    next if $want eq 'error';
    my ( $before, $after ) = ( $lines[ $pairs[$i] ], $fixed[ $pairs[$i] ] );
    isnt( $got, 'error', "$after compiles" );
    is( $got, $want, "$after prints what $before does" );
}

done_testing;
