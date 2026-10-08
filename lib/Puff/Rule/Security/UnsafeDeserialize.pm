package Puff::Rule::Security::UnsafeDeserialize;

use v5.36;
use parent 'Puff::Rule';

use Puff::PPIUtil qw( is_builtin_call is_constant_string );

my %STORABLE_LOADER = map { $_ => 1 } qw( thaw retrieve lock_retrieve fd_retrieve );
my %CODE_SWITCH     = map { $_ => 1 } qw(
    $Storable::Eval
    $YAML::LoadBlessed $YAML::LoadCode $YAML::UseCode
    $YAML::XS::LoadBlessed $YAML::XS::LoadCode $YAML::XS::UseCode
    $YAML::Syck::LoadBlessed $YAML::Syck::LoadCode $YAML::Syck::UseCode $YAML::Syck::EvalCode
);

sub code       {'S012'}
sub summary    {'Do not deserialize untrusted data with Storable or code-loading YAML'}
sub applies_to { [ 'PPI::Token::Word', 'PPI::Token::Symbol' ] }
sub cwe        {502}

sub explanation {
    return <<~'END';
        Storable's thaw and retrieve rebuild objects of whatever classes the
        data names, so data an attacker wrote can run those classes' hooks
        and destructors, and with `$Storable::Eval` set it runs code directly.
        YAML loaders do the same when told to load blessed objects or code
        (CWE-502). YAML and WWW::Mechanize::Cached have both had CVEs for
        this.

        The rule reports:

        - `Storable::thaw`, `Storable::retrieve`, `Storable::lock_retrieve`
          and `Storable::fd_retrieve`, and the same names called as functions
          in a file that loads Storable;
        - setting `$Storable::Eval`, or the LoadBlessed, LoadCode, UseCode or
          EvalCode variables of YAML, YAML::XS or YAML::Syck, to a true
          constant.

        For data that crosses a trust boundary (a cache other users can
        write, a cookie, a socket, an upload) use JSON, or YAML::XS / YAML::PP
        with blessing and code loading left off. When the data was written by
        the same program and nobody else can change it, suppress the
        violation: `# puff: ignore[S012]`. There is no fix.

        Ruff's equivalents are S301 and S506.
        END
}

sub check ( $self, $elem, $doc ) {
    if ( $elem->isa('PPI::Token::Symbol') ) {
        my $name = $elem->symbol;
        return unless $CODE_SWITCH{$name};
        my $op = $elem->snext_sibling;
        return unless $op && $op->isa('PPI::Token::Operator') && $op->content eq '=';
        my $value = $op->snext_sibling;
        return unless $value && _is_true($value);
        return $self->violation( $elem,
            message => "$name loads code or objects from the data (CWE-502); leave it off for untrusted input" );
    }

    my $name = $elem->content;
    my ($func) = $name =~ /\AStorable::(\w+)\z/;
    if ( !defined $func ) {
        return unless $STORABLE_LOADER{$name} && is_builtin_call($elem) && _loads_storable($doc);
        my $next = $elem->snext_sibling;
        return if $next && $next->isa('PPI::Token::Operator') && $next->content ne '.';
        $func = $name;
    }
    return unless $STORABLE_LOADER{$func};
    return $self->violation( $elem,
        message => "Storable $func can run code from untrusted data (CWE-502); use JSON for data you did not write" );
}

sub _is_true ($value) {
    if ( $value->isa('PPI::Token::Number') ) {
        return $value->can('literal') && defined $value->literal && $value->literal != 0;
    }
    return is_constant_string($value) && $value->string ne '' && $value->string ne '0';
}

sub _loads_storable ($doc) {
    return $doc->find_first(
        sub { $_[1]->isa('PPI::Statement::Include') && ( $_[1]->module // '' ) eq 'Storable' }
    ) ? 1 : 0;
}

1;

# ABSTRACT: S012 - do not deserialize untrusted data with Storable or code-loading YAML

__END__

=pod

=head1 DESCRIPTION

Reports Storable's C<thaw> and C<retrieve> family, and turning on code or
object loading in Storable and the YAML modules. There is no fix.

=cut
