package Foo;
sub roll { rand(6) } # expect: S001

package Bar;
sub roll { rand(20) } # expect: S001
1;
