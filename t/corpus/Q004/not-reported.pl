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
