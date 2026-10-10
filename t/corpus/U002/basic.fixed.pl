use v5.36;

my $fh = \*STDOUT;
my $x  = 1;
say "hello"; # expect: U002
say $fh "x: $x"; # expect: U002
say {$fh} "braces"; # expect: U002
say STDERR "to stderr"; # expect: U002
say("parens"); # expect: U002
say qq{qq string}; # expect: U002
say qq {spaced}; # expect: U002
say "a", "b"; # expect: U002
say ""; # expect: U002
say "two\n"; # expect: U002
say "even \\\\"; # expect: U002
say "modifier" if $x; # expect: U002
say "or" or die; # expect: U002
say "a\$"; # expect: U002
say "a@"; # expect: U002
say "@"; # expect: U002
say "pid $$"; # expect: U002
say "$@"; # expect: U002
