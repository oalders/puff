use v5.36;
use Test2::V0;

use Puff::Engine ();
use Puff::Rules  ();
use Puff::Source ();
use Puff::Test   qw( run_corpus );

run_corpus('S009');

my %class = map { $_->code => $_ } Puff::Rules->load;

sub messages ($text) {
    my $result = Puff::Engine->new( rules => [ $class{S009}->new ] )
        ->process_source( Puff::Source->from_string($text), file => 'x.pl' );
    return [ map { $_->message } @{ $result->{violations} } ];
}

# A decimal mode is checked as the mode it really sets and as the octal
# mode it was probably meant to be; the message says which is the problem:
# the real mode is other-writable, or the octal one would be world-writable.
is(
    messages("chmod 755, \$f;\n"),
    ['chmod 755: decimal 755 is mode 01363, which is other-writable (CWE-732); use 0755 or 0644'],
    'decimal chmod whose real mode is other-writable, despite its accidental sticky bit'
);
is(
    messages("umask 77;\n"),
    ['umask 77: decimal 77 is mask 0115, which leaves new files other-writable (CWE-732); use 022 or 077'],
    'decimal umask whose real mask leaves files world-writable'
);
is(
    messages("chmod 777, \$f;\n"),
    [
              'chmod 777: decimal 777 is mode 01411; read as octal 0777 it would make the file world-writable'
            . ' (CWE-732); use 0755 or 0644'
    ],
    'decimal chmod whose intended octal mode is world-writable'
);
is(
    messages("umask 770;\n"),
    [
              'umask 770: decimal 770 is mask 01402; read as octal 0770 it would leave new files world-writable'
            . ' (CWE-732); use 022 or 077'
    ],
    'decimal umask whose intended octal mask leaves files world-writable'
);
is(
    messages("chmod 0777, \$f;\n"),
    ['chmod 0777 makes the file world-writable (CWE-732); use 0755 or 0644'],
    'octal chmod'
);
is(
    messages("chmod 511, \$f;\n"),
    ['chmod 511: decimal 511 is mode 0777, which is other-writable (CWE-732); use 0755 or 0644'],
    'deliberate decimal mode is checked as its real value'
);
is(
    messages("chmod 1023, \$f;\n"),
    ['chmod 1023: decimal 1023 is mode 01777, which is other-writable (CWE-732); use 0755 or 0644'],
    'a sticky bit in the octal reading does not exempt the real mode'
);

# The sticky bit never exempts the real mode of a decimal literal, even when
# the author meant one: 1755 really sets 03333 on a file, not a shared
# directory.
is(
    messages("chmod 1755, \$f;\n"),
    ['chmod 1755: decimal 1755 is mode 03333, which is other-writable (CWE-732); use 0755 or 0644'],
    'a decimal mode meant with a sticky bit is checked without the exemption'
);
is(
    messages("chmod 1022, \$f;\n"),
    ['chmod 1022: decimal 1022 is mode 01776, which is other-writable (CWE-732); use 0755 or 0644'],
    'a decimal mode with an accidental sticky bit is checked without the exemption'
);

# 1777 really sets 03361, which is group-writable but not other-writable, and
# the octal reading 01777 keeps the sticky exemption. B010 reports it.
is( messages("chmod 1777, \$f;\n"), [], 'decimal 1777 is not other-writable' );
is( messages("chmod 01777, \$f;\n"), [], 'an octal sticky mode is still exempt' );

done_testing;
