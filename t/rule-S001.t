use v5.36;
use Test2::V0;

use Puff::Engine ();
use Puff::Rules  ();
use Puff::Source ();
use Puff::Test   qw( run_corpus );

run_corpus('S001');

my ($class) = grep { $_->code eq 'S001' } Puff::Rules->load;

sub run_s001 ( $engine, $text ) {
    return $engine->process_source( Puff::Source->from_string($text), file => 'x.pl' );
}

# The document-wide helpers run once per document, not once per rand call.
{
    my $many = "use strict;\n" . join( q{}, map {"my \$x$_ = rand(10);\n"} 1 .. 200 );
    my %calls;
    my $counted = sub ($helper) {
        my $orig = $class->can($helper);
        return sub { $calls{$helper}++; goto &$orig };
    };
    no strict 'refs';
    no warnings 'redefine';
    local *{"${class}::_has_secure_import"} = $counted->('_has_secure_import');
    local *{"${class}::_import_position"}   = $counted->('_import_position');
    use strict 'refs';

    my $result = run_s001( Puff::Engine->new( rules => [ $class->new ] ), $many );
    is( scalar @{ $result->{violations} }, 200, 'every rand is reported' );
    is( \%calls, { _has_secure_import => 1, _import_position => 1 }, 'helpers run once for one document' );

    %calls  = ();
    $result = run_s001( Puff::Engine->new( rules => [ $class->new ], fix_mode => 'unsafe' ), $many );
    like( $result->{new_text}, qr/\Ause strict;\nuse Crypt::PRNG qw\(rand\);\n/, 'the import is added once' );
    is( $result->{fixed_count}, 200, 'every rand is fixed' );
    is(
        \%calls, { _has_secure_import => 2, _import_position => 2 },
        'helpers run once for the original and once for the fixed document'
    );
}

# One rule object reused across documents does not carry answers over.
{
    my $engine = Puff::Engine->new( rules => [ $class->new ] );
    is(
        run_s001( $engine, "use Crypt::PRNG qw(rand);\nmy \$x = rand;\n" )->{violations}, [],
        'secure import: not reported'
    );
    my $plain = run_s001( $engine, "my \$x = rand;\n" )->{violations};
    is( scalar @$plain, 1, 'next document without the import is reported' );
    is( $plain->[0]->fixable, 1, 'and is fixable' );
    is(
        run_s001( $engine, "package A;\npackage B;\nmy \$x = rand;\n" )->{violations}[0]->fixable, 0,
        'next document with two packages is not fixable'
    );
}

done_testing;
