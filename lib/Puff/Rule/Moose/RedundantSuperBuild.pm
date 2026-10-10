package Puff::Rule::Moose::RedundantSuperBuild;

use v5.36;
use parent 'Puff::Rule';

use Puff::Moose qw( class_include framework package_region );

sub code       {'M004'}
sub summary    {'BUILD or DEMOLISH calls the parent one, which already runs'}
sub applies_to {'PPI::Statement::Sub'}
sub fix_safety {'unsafe'}

my %HOOK = map { $_ => 1 } qw( BUILD DEMOLISH );

sub explanation {
    return <<~'END';
        Moose, Mouse and Moo call every BUILD method in the class hierarchy
        themselves, parents first, after the object is built. They call
        every DEMOLISH too, children first. A BUILD that calls its parent's
        runs that BUILD twice:

            sub BUILD {
                my $self = shift;
                $self->SUPER::BUILD(@_);    # reported; the parent's BUILD ran already
                ...
            }

        The rule reports `$self->SUPER::BUILD`, `->next::method` and
        `->maybe::next::method` inside `sub BUILD`, and the same calls inside
        `sub DEMOLISH`, in a package that uses Moose, Moose::Role, Mouse,
        Mouse::Role, Moo or Moo::Role. Calls inside an anonymous sub in the
        method are not reported.

        The unsafe fix removes the call when it is a statement of its own
        (`$obj->SUPER::BUILD(...);`), and the whole line when nothing else
        is on it. A trailing comment is kept, on its own line at the same
        indentation. When the call's value is used, as in
        `return $self->SUPER::BUILD(@_)`, there is no fix. It is unsafe
        because a parent that is not a Moose, Mouse or Moo class may rely
        on the call, and because any arguments the call changed are no
        longer passed.
        END
}

sub check ( $self, $elem, $doc ) {
    my $name = $elem->name // return;
    return unless $HOOK{$name};
    my $block  = $elem->block                           or return;
    my $class  = class_include( package_region($elem) ) or return;
    my $module = framework($class)->{module};

    my $calls = $block->find(
        sub ( $top, $el ) {
            return 0 unless $el->isa('PPI::Token::Word');
            my $content = $el->content;
            return 0 unless $content eq "SUPER::$name" || $content =~ /\A(?:maybe::)?next::method\z/;
            my $arrow = $el->sprevious_sibling;
            return 0 unless $arrow && $arrow->isa('PPI::Token::Operator') && $arrow->content eq '->';
            return _owner_block($el) == $block;
        }
    ) or return;

    return map {
        $self->violation(
            $_,
            message => "$name calls " . $_->content . "; $module already calls every $name in the hierarchy",
            fixable => _standalone($_) ? 1 : 0,
        )
    } @$calls;
}

sub fix ( $self, $violation, $fix ) {
    my $statement = _standalone( $violation->element ) or return 0;
    my $src       = $fix->source;
    my $text      = $src->text;
    my $start     = $src->start_of($statement);
    my $end       = $src->end_of($statement);

    my $line_start = rindex( $text, "\n", $start - 1 ) + 1;
    my $line_end   = index( $text, "\n", $end );
    $line_end = length $text if $line_end < 0;
    my $before = substr( $text, $line_start, $start - $line_start );
    my $after  = substr( $text, $end, $line_end - $end );

    if ( $before =~ /\A[ \t]*\z/ && $after =~ /\A[ \t]*\z/ ) {
        $fix->replace_range( $line_start, $line_end < length $text ? $line_end + 1 : $line_end, q{} );
        return 1;
    }
    my ($space) = $after =~ /\A([ \t]*)/;
    $fix->replace_range( $start, $end + length $space, q{} );
    return 1;
}

# The block of the named sub or anonymous sub that $el is in.
sub _owner_block ($el) {
    my $node = $el->parent;
    while ($node) {
        if ( $node->isa('PPI::Structure::Block') ) {
            my $parent = $node->parent;
            return $node if $parent && $parent->isa('PPI::Statement::Sub');
            my $prev = $node->sprevious_sibling;
            $prev = $prev->sprevious_sibling
                while $prev && ( $prev->isa('PPI::Token::Prototype') || $prev->isa('PPI::Structure::List') );
            return $node if $prev && $prev->isa('PPI::Token::Word') && $prev->content eq 'sub';
        }
        $node = $node->parent;
    }
    return 0;
}

# The statement when the call is all of it (`$self->SUPER::BUILD(@_);`).
sub _standalone ($word) {
    my $statement = $word->parent;
    return unless ref $statement eq 'PPI::Statement';
    my @children = $statement->schildren;
    pop @children if $children[-1]->isa('PPI::Token::Structure') && $children[-1]->content eq ';';
    pop @children if @children == 4                              && $children[-1]->isa('PPI::Structure::List');
    return unless @children == 3                                 && $children[2] == $word;
    return unless $children[0]->isa('PPI::Token::Symbol')        && $children[0]->raw_type eq '$';
    return if $statement->find_first('PPI::Token::HereDoc');
    return $statement;
}

1;

# ABSTRACT: M004 - BUILD or DEMOLISH calls the parent one, which already runs

__END__

=pod

=head1 DESCRIPTION

Reports C<< ->SUPER::BUILD >>, C<< ->next::method >> and
C<< ->maybe::next::method >> inside C<sub BUILD>, and the C<DEMOLISH>
equivalents inside C<sub DEMOLISH>, in a package that uses Moose,
Moose::Role, Mouse, Mouse::Role, Moo or Moo::Role. Those frameworks call
every BUILD and DEMOLISH in the hierarchy already, so the parent's runs
twice.

The unsafe fix removes the call when it is a statement of its own, with its
line when nothing else is on it. A trailing comment stays where it was. A call whose value is used is reported
with no fix.

Not selected by default; select it with C<M> or C<M004>.

=cut
