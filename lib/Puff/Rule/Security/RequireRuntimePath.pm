package Puff::Rule::Security::RequireRuntimePath;

use v5.36;
use parent 'Puff::Rule';

use Puff::PPIUtil qw( is_constant_string );

sub code       {'S016'}
sub summary    {'Do not require or do a file name computed at runtime'}
sub applies_to {'PPI::Token::Word'}
sub cwe        {829}

sub explanation {
    return <<~'END';
        `require $file` and `do $file` load and run whatever Perl file the
        value names. When any part of the name comes from outside (a request
        parameter, a config file, a plugin name in a database), an attacker
        can load a file they wrote, or walk out of the intended directory
        with `../` (CWE-829, inclusion of functionality from an untrusted
        control sphere).

        The rule reports `require` and `do` with an argument that is not a
        bareword module name, a version or a constant string: `require
        $file`, `require "$dir/$name.pm"`, `do "$repo/.env.pl"`. It does not
        report `do { ... }` blocks.

        It is not reported when the same sub (or the file, outside a sub)
        checks a value against a module-name pattern such as
        `/\A\w+(?:::\w+)*\z/`. Load classes with Module::Runtime's
        `require_module`, which checks the name, after checking it against
        an allowlist. There is no fix.
        END
}

sub check ( $self, $elem, $doc ) {
    my $word = $elem->content;
    return unless $word eq 'require' || $word eq 'do';
    my $prev = $elem->sprevious_sibling;
    return if $prev && $prev->isa('PPI::Token::Operator') && $prev->content eq '->';
    my $arg = $elem->snext_sibling or return;
    $arg = ( $arg->schildren )[0] if $arg->isa('PPI::Structure::List') && $arg->schildren == 1;
    $arg = ( $arg->schildren )[0] if $arg && $arg->isa('PPI::Statement::Expression');
    return unless $arg;
    return if $arg->isa('PPI::Structure::Block');
    return if $arg->isa('PPI::Token::Word') || $arg->isa('PPI::Token::Number');
    return if $arg->isa('PPI::Token::Structure') || $arg->isa('PPI::Token::Operator');
    return unless _uses_runtime_value($elem);
    return if _checks_module_name($elem);
    return $self->violation( $elem, message => "$word of a file name computed at runtime (CWE-829); check it against an allowlist, or use require_module" );
}

my %STOP = map { $_ => 1 } qw( or and if unless xor );

# Whether the argument after $word mentions a variable or interpolates one.
sub _uses_runtime_value ($word) {
    for ( my $el = $word->snext_sibling; $el; $el = $el->snext_sibling ) {
        last if $el->isa('PPI::Token::Structure') && $el->content eq ';';
        last if ( $el->isa('PPI::Token::Operator') || $el->isa('PPI::Token::Word') ) && $STOP{ $el->content };
        my @tokens = $el->isa('PPI::Node') ? @{ $el->find('PPI::Token') || [] } : ($el);
        for my $token (@tokens) {
            return 1 if $token->isa('PPI::Token::Symbol') && $token->symbol =~ /\A.\w/;
            return 1 if $token->isa('PPI::Token::Quote') && !is_constant_string($token);
        }
    }
    return 0;
}

# A module-name check: an anchored pattern with \w and ::.
my $NAME_CHECK = qr/ (?: \A \^ | \\A ) .* \\w .* :: .* (?: \$ | \\z ) \z /x;

sub _checks_module_name ($elem) {
    my $scope = $elem;
    while ( $scope = $scope->parent ) {
        last if $scope->isa('PPI::Statement::Sub') || $scope->isa('PPI::Document');
    }
    return 0 unless $scope;
    return $scope->find_first( sub ( $top, $el ) {
        return 0 unless $el->isa('PPI::Token::Regexp::Match') || $el->isa('PPI::Token::QuoteLike::Regexp');
        my $pattern = $el->get_match_string // return 0;
        return $pattern =~ $NAME_CHECK;
    } ) ? 1 : 0;
}

1;

# ABSTRACT: S016 - do not require or do a file name computed at runtime

__END__

=pod

=head1 DESCRIPTION

Reports C<require> and C<do> of a file name computed at runtime, unless the
code checks a module name against an anchored pattern first. There is no
fix.

=cut
