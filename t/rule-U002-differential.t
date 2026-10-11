use v5.36;
use Test2::V0;

use Path::Tiny qw( tempdir );

use lib 't/lib';
use Puff::Engine ();
use Puff::Rules  ();
use Puff::Source ();
use TestCommand  qw( run_capture );

# Every string over an alphabet that ends in `\n`, as `print "...";`, up
# to length 3, and every 7th string of length 4. Where U002 fixes one, the
# `say` it becomes must compile and print the same bytes. One perl process
# compiles and runs each statement on its own (a string eval compiles as
# perl -c does), without strict, with $\ unset and with variables named
# `a` and `n` set, and prints its output in hex, or `error` if it does not
# compile.

my @alphabet = ( 'a', '$', '@', '\\', 'n', '{', '}', q{ }, qw( ^ : [ ] - > ), q{,}, qw| ( ) 0 | );
my @bodies   = (q{});
my @level    = (q{});
for my $length ( 1 .. 4 ) {
    @level = map {
        my $s = $_;
        map { $s . $_ } @alphabet
    } @level;
    my $step = $length == 4 ? 7 : 1;
    push @bodies, @level[ grep { !( $_ % $step ) } 0 .. $#level ];
}
my @lines = map {qq{print "$_\\n";}} @bodies;

# Each line is fixed on its own, since a `$\` anywhere in a file withholds
# every fix in it.
my ($class) = grep { $_->code eq 'U002' } Puff::Rules->load;
my $engine = Puff::Engine->new( rules => [ $class->new ], fix_mode => 'unsafe' );
my @fixed;
for my $line (@lines) {
    my $text   = qq{use feature 'say';\n$line\n};
    my $result = $engine->process_source( Puff::Source->from_string($text), file => 'x.pl' );
    die $result->{error} if $result->{error};
    my @got = split /\n/, $result->{new_text} // $text;
    die "lost lines in $line" unless @got == 2;
    push @fixed, $got[1];
}

my $DRIVER = <<'END';
our ( $a, $n ) = ( 'A', 'N' );
our @a = ( 1, 2 );
our @n = ( 3, 4 );
our %a = ( a => 'v', n => 'w', 0 => 'z' );
our %n = %a;
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

# A count that falls means fixes are being withheld; one that rises needs
# the new fixes checked. Strings with no `$`, `@` or `\` are always fixed.
is( scalar @pairs, 16_554, 'the expected number of fixes is offered' );
my @plain = grep { $bodies[$_] !~ /[\$\@\\]/ } 0 .. $#bodies;
is( [ grep { $fixed[$_] eq $lines[$_] } @plain ], [], 'every string with no $, @ or \\ is fixed' );

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
