use strict;
use warnings;

sub foo { return @_ }
my $code = \&foo;
my $x    = 1;
my $r    = \&foo;
my $s    = \ &foo;
my @refs = \(&foo);
local *bar = \&foo;
print "yes\n" if defined &foo;
print "yes\n" if defined(&foo);
print "yes\n" if exists &foo;
print "yes\n" if exists(&foo);
&$code(1);
&{$code}(1);
&$code->(1);
&{"foo"}() if 0;
&CORE::say(1);
my $n = $x &foo;
my $m = $x&foo();
my $k = 3 & foo();
my $j = ( $x + 1 ) &foo;
my @l = sort &foo, 1;
undef &foo if 0;
sub baz { goto &foo }
sub qux ($) { return 1 }
foo(1);
qux(2);
my $h = { cb => \&foo };

# Bitwise `&` after a term: Perl expects an operator there, so `&` is not a
# sigil.
sub func { return 1 }
sub bar  { return 2 }
{
    no strict;
    no warnings;
    my ( %h, @x, $z, $i );
    my $b1 = $a &foo;
    my $b2 = $h{x} & foo();
    my $b3 = func(1) &bar;
    my $b4 = $x[0] &bar(1);
    my $b5 = (1) &bar(2);
    my $b6 = $x &$z;
    my $b7 = $i++ &foo;
    my $b8 = $i-- &foo(1);
}

# A symbolic or code-ref call has no plain name to call instead.
&{"foo"}(1) if 0;

# `&foo::(1)` calls a sub named `foo::`; `foo::(1)` is a syntax error.
&foo::(1) if 0;

# Calls the rule does not report, to stay conservative: `&foo` after a
# filehandle or a block.
print STDERR &foo(1);
my $fh = \*STDERR;
print {$fh} &foo(1);
my @gb = grep { 1 } &foo(1);
my @mb = map { $_ } &foo(1);
