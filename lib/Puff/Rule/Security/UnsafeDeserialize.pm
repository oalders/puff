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

# Modules whose Load blesses objects unless LoadBlessed is turned off.
my @BLESSING_YAML = qw( YAML::XS YAML );
my %YAML_LOADER   = map { $_ => 1 } qw( Load LoadFile );

sub code       {'S012'}
sub summary    {'Do not deserialize untrusted data with Storable or code-loading YAML'}
sub applies_to { [ 'PPI::Token::Word', 'PPI::Token::Symbol' ] }
sub fix_safety {'unsafe'}
sub cwe        {502}

sub explanation {
    return <<~'END';
        Storable's thaw and retrieve rebuild objects of whatever classes the
        data names, so data an attacker wrote can run those classes' hooks
        and destructors, and with `$Storable::Eval` set it runs code directly.
        YAML loaders do the same when told to load blessed objects or code
        (CWE-502).

        The rule reports:

        - `Storable::thaw`, `Storable::retrieve`, `Storable::lock_retrieve`
          and `Storable::fd_retrieve`, and the same names called as functions
          in a file that loads Storable;
        - setting `$Storable::Eval`, or the LoadBlessed, LoadCode, UseCode or
          EvalCode variables of YAML, YAML::XS or YAML::Syck, to a true
          constant;
        - `Load` and `LoadFile` of YAML or YAML::XS (by full name, or called
          as functions in a file that loads the module), when the file never
          sets that module's `$LoadBlessed` to a false constant. Both
          modules bless objects by default.

        For data that crosses a trust boundary (a cache other users can
        write, a cookie, a socket, an upload) use JSON, or YAML::XS / YAML::PP
        with blessing and code loading left off. When the data was written by
        the same program and nobody else can change it, suppress the
        violation: `# puff: ignore S012`.

        The unsafe fix wraps a YAML `Load(...)` or `LoadFile(...)` call as
        `do { local $YAML::XS::LoadBlessed = 0; Load(...) }`. It is unsafe
        because data that relied on blessed objects now loads as plain
        hashes and arrays. Storable is not fixed.

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
            message => "$name loads code or objects from the data (CWE-502); leave it off for untrusted input",
            fixable => 0,
        );
    }

    if ( my $module = $self->_yaml_loader( $elem, $doc ) ) {
        return $self->violation(
            $elem,
            message => "$module blesses objects named by the data (CWE-502); set \$${module}::LoadBlessed = 0",
            fixable => _call_list($elem) ? 1 : 0,
        );
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
        message => "Storable $func can run code from untrusted data (CWE-502); use JSON for data you did not write",
        fixable => 0,
    );
}

sub fix ( $self, $violation, $fix ) {
    my $word   = $violation->element;
    my $module = $self->_yaml_loader( $word, $word->top ) or return 0;
    my $list   = _call_list($word)                       or return 0;
    my $source = $fix->source;
    my $start  = $source->start_of($word);
    my $end    = $source->end_of($list);
    my $call   = substr $source->text, $start, $end - $start;
    $fix->replace_range( $start, $end, "do { local \$${module}::LoadBlessed = 0; $call }" );
    return 1;
}

# The YAML module whose blessing Load or LoadFile $word calls, or undef.
sub _yaml_loader ( $self, $word, $doc ) {
    return unless $word->isa('PPI::Token::Word');
    my $name = $word->content;
    my $module;
    if ( $name =~ /\A(.+)::(\w+)\z/ ) {
        return unless $YAML_LOADER{$2} && grep { $_ eq $1 } @BLESSING_YAML;
        return unless is_builtin_call($word);
        $module = $1;
    }
    else {
        return unless $YAML_LOADER{$name} && is_builtin_call($word);
        ($module) = grep { _loads( $doc, $_ ) } @BLESSING_YAML or return;
    }
    return if _turns_off_blessing( $doc, $module, $word );
    return $module;
}

# The (...) argument list right after a function name, or undef.
sub _call_list ($word) {
    my $list = $word->snext_sibling;
    return $list && $list->isa('PPI::Structure::List') ? $list : undef;
}

# Whether $module's LoadBlessed is set to a false constant where it covers
# $word: anywhere in the file, or for `local`, earlier in a block around it.
sub _turns_off_blessing ( $doc, $module, $word ) {
    my $name = "\$${module}::LoadBlessed";
    return $doc->find_first( sub ( $top, $el ) {
        return 0 unless $el->isa('PPI::Token::Symbol') && $el->symbol eq $name;
        my $op = $el->snext_sibling;
        return 0 unless $op && $op->isa('PPI::Token::Operator') && $op->content eq '=';
        my $value = $op->snext_sibling;
        return 0 unless $value && !_is_true($value) && ( $value->isa('PPI::Token::Number') || is_constant_string($value) );
        my $local = $el->sprevious_sibling;
        return 1 unless $local && $local->isa('PPI::Token::Word') && $local->content eq 'local';
        my $statement = $el->statement or return 0;
        my $scope     = $statement->parent;
        return $scope->isa('PPI::Document') || ( $word->descendant_of($scope) && _after( $word, $statement ) );
    } ) ? 1 : 0;
}

sub _after ( $word, $statement ) {
    my @word = @{ $word->location // [0] };
    my @stmt = @{ $statement->location // [0] };
    return $word[0] > $stmt[0] || ( $word[0] == $stmt[0] && $word[1] > $stmt[1] );
}

sub _is_true ($value) {
    if ( $value->isa('PPI::Token::Number') ) {
        return $value->can('literal') && defined $value->literal && $value->literal != 0;
    }
    return is_constant_string($value) && $value->string ne '' && $value->string ne '0';
}

sub _loads_storable ($doc) { return _loads( $doc, 'Storable' ) }

sub _loads ( $doc, $module ) {
    return $doc->find_first(
        sub { $_[1]->isa('PPI::Statement::Include') && ( $_[1]->module // '' ) eq $module }
    ) ? 1 : 0;
}

1;

# ABSTRACT: S012 - do not deserialize untrusted data with Storable or code-loading YAML

__END__

=pod

=head1 DESCRIPTION

Reports Storable's C<thaw> and C<retrieve> family, turning on code or
object loading in Storable and the YAML modules, and YAML or YAML::XS
C<Load> with blessing left on. The unsafe fix turns blessing off around a
YAML C<Load> call.

=cut
