my $x;
eval { 1 };
eval { die 'x' } or warn $@;
eval "use Foo; 1";
eval 'use Foo; 1';
eval q{ require Foo };
eval qq{ require Foo };
eval("1");
eval "cost \$5";
eval <<'EOT';
$x
EOT
eval <<"EOT";
plain
EOT
$obj->eval($x);
my %h = ( eval => $x );
print $h{eval};
sub eval_it { }
