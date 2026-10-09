package Puff::Rule::Moose::NamespaceAutoclean;

use v5.36;
use parent 'Puff::Rule';

use Puff::Moose qw( class_include framework package_name package_region package_statements same_package );

sub code       {'M005'}
sub summary    {'Moose sugar left in the namespace'}
sub applies_to {'PPI::Statement::Include'}
sub fix_safety {'unsafe'}

my %CLEANER   = map { $_ => 1 } qw( namespace::autoclean namespace::clean namespace::sweep );
my %FRAMEWORK = map { $_ => 1 } qw( Moose Moose::Role Mouse Mouse::Role Moo Moo::Role );

sub explanation {
    return <<~'END';
        `use Moose` imports `has`, `extends`, `with`, `before`, `after`,
        `around` and friends into the class. They stay there after the
        class is built, so they can be called as methods (`$obj->has`), and
        a method of the same name in a subclass or role clashes with them.
        Remove them once the class is compiled:

            use Moose;
            use namespace::autoclean;

        The rule reports `use Moose`, `use Moose::Role`, `use Mouse`,
        `use Mouse::Role`, `use Moo` or `use Moo::Role` in a package that
        has no `use namespace::autoclean`, `use namespace::clean` or
        `use namespace::sweep`, and no `no Moose` (or `no Mouse`, `no Moo`,
        or a `::Role` one). Packages are checked one at a time, so in a
        file with several classes each needs its own. `use Moose ()`, which
        imports nothing, is not reported, and a package with more than one
        such `use` is reported once.

        The unsafe fix adds `use namespace::autoclean;` on its own line
        after the `use Moose;`, with the same indentation. It is not offered
        when other code shares the line, or the `use` has no semicolon. It
        is unsafe because namespace::autoclean also removes every other
        imported function from the package, such as `blessed` or
        `try`, which breaks code that calls one as a method or by its
        full name (`__PACKAGE__->blessed`, `My::Class::blessed`), and
        because the module must be installed. namespace::autoclean works
        with Moo too; namespace::clean, which many Moo users choose, is
        accepted as well.
        END
}

sub check ( $self, $elem, $doc ) {
    my $framework = framework($elem) or return;
    my $region    = package_region($elem);
    my $first     = class_include($region);
    return unless $first && same_package( $first, $elem );
    return if _cleaned($region);
    my $name = package_name($region);
    return $self->violation(
        $elem,
        message => "Package $name uses $framework->{module} without namespace::autoclean or no $framework->{module}",
        fixable => _insert_point($elem),
    );
}

sub fix ( $self, $violation, $fix ) {
    my $include = $violation->element;
    my $src     = $fix->source;
    my ( $at, $indent ) = _line_end( $include, $src ) or return 0;
    $fix->replace_range( $at, $at, "\n${indent}use namespace::autoclean;" );
    return 1;
}

sub _cleaned ($region) {
    for my $statement ( package_statements($region) ) {
        next unless $statement->isa('PPI::Statement::Include');
        my $type   = $statement->type   // next;
        my $module = $statement->module // next;
        return 1 if $type eq 'use' && $CLEANER{$module};
        return 1 if $type eq 'no'  && $FRAMEWORK{$module};
    }
    return 0;
}

# Whether the fix can insert after $include: it ends with `;` and only
# whitespace comes before it and only a comment after it on its line.
sub _insert_point ($include) {
    my $last = $include->schild(-1);
    return 0 unless $last && $last->isa('PPI::Token::Structure') && $last->content eq ';';
    my $prev = $include->previous_token;
    $prev = $prev->previous_token while $prev && $prev->isa('PPI::Token::Whitespace') && $prev->content !~ /\n/;
    return 0 if $prev && $prev->content !~ /\n[ \t]*\z/;
    my $next = $last->next_token;
    $next = $next->next_token while $next && $next->isa('PPI::Token::Whitespace') && $next->content !~ /\n/;
    return !$next || $next->isa('PPI::Token::Comment') || $next->isa('PPI::Token::Whitespace') ? 1 : 0;
}

# The offset of the end of $include's line and its indentation, or ().
sub _line_end ( $include, $src ) {
    return unless _insert_point($include);
    my $text  = $src->text;
    my $start = $src->start_of($include);
    my $end   = $src->end_of($include);
    my $line  = rindex( $text, "\n", $start - 1 ) + 1;
    my $after = index( $text, "\n", $end );
    $after = length $text if $after < 0;
    return ( $after, substr( $text, $line, $start - $line ) );
}

1;

# ABSTRACT: M005 - Moose sugar left in the namespace

__END__

=pod

=head1 DESCRIPTION

Reports C<use Moose> (or Moose::Role, Mouse, Mouse::Role, Moo, Moo::Role) in
a package with no C<use namespace::autoclean>, C<use namespace::clean> or
C<use namespace::sweep> and no C<no Moose> (or the matching C<no>). The
imported sugar (C<has>, C<extends>, C<with>, ...) otherwise stays callable as
methods of the class.

The unsafe fix adds C<use namespace::autoclean;> on its own line after the
C<use>, with the same indentation, when the C<use> ends with a semicolon and
only a comment shares its line. It is unsafe because namespace::autoclean
removes every imported function, not only the Moose sugar.

Not selected by default; select it with C<M> or C<M005>.

=cut
