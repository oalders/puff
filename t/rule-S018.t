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
    messages("system('ls -l | wc -l > out');\n"),
    ['system command string runs /bin/sh (shell syntax: | >); pass the command and its arguments as a list'],
    'system message lists the shell syntax'
);
is(
    messages("CORE::exec('FOO=1 make');\nexec('. ./env');\nexec('exec make');\nsystem(\"a\\nb\");\n"),
    [
        'exec command string runs /bin/sh (shell syntax: VAR= assignment); pass the command and its arguments as a list',
        'exec command string runs /bin/sh (shell syntax: . command); pass the command and its arguments as a list',
        'exec command string runs /bin/sh (shell syntax: exec command); pass the command and its arguments as a list',
        'system command string runs /bin/sh (shell syntax: newline); pass the command and its arguments as a list',
    ],
    'first-word and newline messages, CORE:: dropped'
);
is(
    messages("my \$x = `ls -l | wc`;\nmy \$y = qx{ls *};\nmy \$z = readpipe('date; uname');\n"),
    [
        'Command string runs /bin/sh (shell syntax: |); capture output with IPC::Run3 or Capture::Tiny and a list',
        'Command string runs /bin/sh (shell syntax: *); capture output with IPC::Run3 or Capture::Tiny and a list',
        'readpipe command string runs /bin/sh (shell syntax: ;); capture output with IPC::Run3 or Capture::Tiny and a list',
    ],
    'capture messages'
);
is( messages("system('ls -l');\nmy \$x = `ls -l`;\n"), [], 'no shell syntax, no report' );
is( $class->fix_safety, 'none', 'fix safety is none' );
ok( !( grep { $_->fixable } @{ violations("system('ls | wc');\n") } ), 'not fixable' );

# S008 and S018 never report the same call.
my ($s008) = grep { $_->code eq 'S008' } @classes;
my $both = <<'END';
my ( $f, $cmd );
system("ls $f");
system($cmd);
system('ls -l | wc');
my $x = `ls $f`;
$x = `ls -l | wc`;
$x = qx'ls $HOME';
$x = qx{ls \$HOME};
system(('ls | wc'));
system(<<"X");
ls $f | wc
X
system(<<'X');
ls $f | wc
X
system('ls -l');
$x = `ls -l`;
END
my $result = Puff::Engine->new( rules => [ $class->new, $s008->new ] )
    ->process_source( Puff::Source->from_string($both), file => 'x.pl' );
my %lines;
push @{ $lines{ $_->line } }, $_->code for @{ $result->{violations} };
is(
    \%lines,
    {
        2 => ['S008'], 3 => ['S008'], 4  => ['S018'], 5  => ['S008'], 6 => ['S018'], 7 => ['S018'],
        8 => ['S018'], 9 => ['S018'], 10 => ['S008'], 13 => ['S018'],
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
$file->spew_utf8("system('ls -l | wc');\n");
my $out = run_capture( undef, @puff, '--select', 'S', "$file" );
unlike( $out, qr/S018/, '--select S does not enable S018' );
$out = run_capture( undef, @puff, '--select', 'S018', "$file" );
like( $out, qr/:1:1: S018 system command string runs \/bin\/sh/, '--select S018 enables it' );
is( $? >> 8, 1, 'and exits 1' );

done_testing;
