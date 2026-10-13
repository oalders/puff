use v5.36;
'a' =~ /a(?{ $\ = "" })/;
print "x\n"; # expect: U002
