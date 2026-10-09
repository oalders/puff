use v5.36;
use Test2::V0;

use lib 't/lib';
use TestCommand qw( run_capture );

use Cwd        qw( getcwd );
use Path::Tiny qw( path tempdir );

use Puff::Engine ();
use Puff::Rules  ();
use Puff::Source ();
use Puff::Test   qw( run_corpus );

run_corpus('S018');

my @classes = Puff::Rules->load;
my ($class) = grep { $_->code eq 'S018' } @classes;

sub violations ($text) {
    my $result = Puff::Engine->new( rules => [ $class->new ] )
        ->process_source( Puff::Source->from_string($text), file => 'x.pl' );
    return $result->{violations};
}

sub messages ($text) {
    return [ map { $_->message } @{ violations($text) } ];
}

is(
    messages("system('ls -l');\n"),
    ['system given as one string; pass the command as a list'],
    'plain command message'
);
is(
    messages("CORE::exec('ls | wc');\n"),
    ['exec with shell syntax in one string runs /bin/sh (CWE-78); pass the command as a list'],
    'shell syntax message, CORE:: dropped'
);
is(
    messages("my \$x = `ls -l`;\nmy \$y = qx{ls -l | wc -l};\n"),
    [
        'Command given as one string; use IPC::Run3 or Capture::Tiny with a list',
        'Command with shell syntax in one string runs /bin/sh (CWE-78); use IPC::Run3 or Capture::Tiny with a list',
    ],
    'backtick messages'
);
is(
    messages("my \$x = readpipe('ls -l');\n"),
    ['readpipe given as one string; use IPC::Run3 or Capture::Tiny with a list'],
    'readpipe message'
);
is(
    [ map { $_->fixable ? 1 : 0 } @{ violations("system('ls -l');\nsystem('ls *');\nmy \$x = `ls -l`;\n") } ],
    [ 1, 0, 0 ], 'only the plain system string is fixable'
);
is( $class->fix_safety, 'unsafe', 'fix safety is unsafe' );

# S008 and S018 never report the same call.
my ($s008) = grep { $_->code eq 'S008' } @classes;
my $both = <<'END';
my ( $f, $cmd );
system("ls $f");
system($cmd);
system('ls -l');
my $x = `ls $f`;
$x = `ls -l`;
$x = qx'ls $HOME';
$x = qx{ls \$HOME};
END
my $result = Puff::Engine->new( rules => [ $class->new, $s008->new ] )
    ->process_source( Puff::Source->from_string($both), file => 'x.pl' );
my %lines;
push @{ $lines{ $_->line } }, $_->code for @{ $result->{violations} };
is(
    \%lines,
    {
        2 => ['S008'], 3 => ['S008'], 4 => ['S018'], 5 => ['S008'], 6 => ['S018'], 7 => ['S018'],
        8 => ['S018'],
    },
    'each call is reported by exactly one of S008 and S018'
);

sub selected (@select) {
    return [ grep { $_ eq 'S018' } map { $_->code } Puff::Rules->instantiate( \@classes, select => [@select] ) ];
}
is( selected( 'S', 'B' ), [], 'not selected by the default prefixes' );
is( selected('S01'), [], 'not selected by a longer prefix' );
is( selected('S018'), ['S018'], 'selected by its exact code' );
is( selected('ALL'), ['S018'], 'selected by ALL' );

# Through the CLI: the prefix S does not enable the rule, its code does.
my $root = path(getcwd)->absolute;
my @puff = (
    $^X, '-I' . $root->child('lib'), '-I' . $root->child( 'local', 'lib', 'perl5' ),
    $root->child( 'bin', 'puff' )->stringify, 'check', '--no-config',
);
my $dir  = tempdir();
my $file = $dir->child('x.pl');
$file->spew_utf8("system('ls -l');\n");
my $out = run_capture( undef, @puff, '--select', 'S', "$file" );
unlike( $out, qr/S018/, '--select S does not enable S018' );
$out = run_capture( undef, @puff, '--select', 'S018', "$file" );
like( $out, qr/:1:1: S018 system given as one string/, '--select S018 enables it' );
is( $? >> 8, 1, 'and exits 1' );

done_testing;
