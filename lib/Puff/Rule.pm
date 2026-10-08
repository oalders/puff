package Puff::Rule;

use v5.36;

use Puff::Violation ();

sub new ( $class, %args ) {
    return bless { options => $args{options} // {} }, $class;
}

sub code        {''}
sub summary     {''}
sub explanation {''}
sub applies_to  {'PPI::Element'}
sub fix_safety  {'none'}
sub options     { {} }
sub cwe         { () }

sub check ( $self, $elem, $doc ) { return }
sub fix ( $self, $violation, $fix ) { return 0 }

sub option ( $self, $name ) {
    die 'rule ' . $self->code . " has no option $name\n" unless exists $self->options->{$name};
    my $configured = $self->{options};
    return $configured->{$name} if exists $configured->{$name};
    return $self->options->{$name};
}

sub violation ( $self, $elem, %args ) {
    my $loc = $elem->location or die "PPI element has no location\n";
    my $fixable = $self->fix_safety eq 'none' ? 0 : ( $args{fixable} // 1 );
    return Puff::Violation->new(
        rule    => $self,
        code    => $self->code,
        element => $elem,
        line    => $loc->[0],
        column  => $loc->[1],
        message => $args{message} // $self->summary,
        fixable => $fixable ? 1 : 0,
    );
}

1;

# ABSTRACT: Base class for puff rules

__END__

=pod

=head1 SYNOPSIS

    package Local::Rule::NoFixme;
    use v5.36;
    use parent 'Puff::Rule';

    sub code       {'X001'}
    sub summary    {'Use TODO instead of FIXME'}
    sub applies_to {'PPI::Token::Comment'}
    sub fix_safety {'safe'}

    sub check ( $self, $elem, $doc ) {
        return unless $elem->content =~ /\bFIXME\b/;
        return $self->violation( $elem, message => 'Use TODO instead of FIXME' );
    }

    sub fix ( $self, $violation, $fix ) {
        my $elem = $violation->element;
        return 0 unless $elem->content =~ /\bFIXME\b/;
        my $start = $fix->source->start_of($elem) + $-[0];
        $fix->replace_range( $start, $start + 5, 'TODO' );
        return 1;
    }

=head1 DESCRIPTION

Every puff rule is a subclass of Puff::Rule. The engine parses each file
with L<PPI>, finds the elements each rule asks for with C<applies_to>, calls
C<check> on each one and collects the violations. When fixing, it calls
C<fix> for the violations that are fixable in the current fix mode. See the
README for how to load your own rules (the C<rule-paths> setting) and how to
test them.

A rule is stateless between files: the engine creates one object per run
and calls C<check> and C<fix> on it for every file, so do not keep
per-file data in the object.

=head1 METHODS TO OVERRIDE

The first six are class-level declarations and take no arguments. Define
them as constants (C<< sub code {'X001'} >>).

=head2 code

The rule's code: one or more capital letters followed by exactly three
digits (C<S001>, C<X042>). It must match C</\A[A-Z]+[0-9]{3}\z/> and be
unique among the loaded rules. C<P001> is reserved for the engine. Puff
refuses to start if a code is invalid or used twice. Users select, ignore
and suppress rules by this code or a prefix of it.

=head2 summary

One line describing the rule. Shown by C<puff rules> and C<puff rule CODE>.

=head2 explanation

Longer text shown by C<puff rule CODE>: why the code is a problem, what is
reported, what the fix does, and when it declines. Default is the empty
string.

=head2 applies_to

A PPI class name, or an array reference of class names, that C<check> is
interested in. The engine calls C<check> once for every element in the
document that C<isa> one of them. Default C<PPI::Element>, which sends every
element and is slow; name something narrower, such as C<PPI::Token::Word>.

=head2 fix_safety

C<safe>, C<unsafe> or C<none> (the default). C<safe> fixes are applied by
C<--fix>; C<unsafe> fixes also need C<--unsafe-fixes>; a C<none> rule has no
fix and its violations are never fixable. Use C<unsafe> for any fix that can
change what the program does.

=head2 cwe

The CWE (Common Weakness Enumeration, L<https://cwe.mitre.org/>) ids this
rule detects, as a list of numbers: C<sub cwe { ( 78, 73 ) }>. C<puff rule>
prints them. Default: an empty list.

=head2 options

A hash reference of option names to default values. Users set options in a
C<[rules.CODE]> table in F<.puff.toml>. Puff dies if the configuration
names an option that is not a key of this hash. Default C<{}>.

=head2 check

    sub check ( $self, $elem, $doc ) { ... }

Called for each element matching C<applies_to>. C<$elem> is the element and
C<$doc> is the whole L<PPI::Document>. Return a list of violations made with
L</violation>, or return nothing. C<check> runs on every pass of the fix
loop, so it must give the same answer for the same text. If it dies, puff
reports an error for the file (exit code 2) and applies no fixes to it.

Decide here whether a fix is possible and pass C<< fixable => 0 >> to
L</violation> when it is not, so the report does not promise a fix that
C<fix> will decline.

=head2 fix

    sub fix ( $self, $violation, $fix ) { ... }

Called for a violation whose C<fixable> is true and whose rule's
C<fix_safety> is allowed in the current mode. Record edits on the
L</"Puff::Fix object"> C<$fix> and return true. To decline (leave this
violation unfixed, with no error), return false, record no edits, or call
C<< Puff::Fix->decline($why) >>; any edits already recorded are thrown away.
If C<fix> dies any other way, puff reports C<rule CODE fix failed: MESSAGE>
as an error for the file (exit code 2) and writes none of the file's
fixes.

C<< $violation->element >> is the PPI element C<check> was given. Edits are
text offsets, not tree changes: do not modify the PPI tree.

Several violations may be fixed in one pass. Fixes whose edits overlap are
deferred to the next pass, after the file has been re-parsed and re-linted,
and identical edits from different fixes are applied once. Make the fix
leave no fixable violation of the same rule behind, or the loop will run to
its limit of 10 passes and report an error.

The default C<fix> returns false.

=head1 METHODS TO CALL

=head2 option

    my $value = $self->option('name');

The value configured for C<name> in C<[rules.CODE]>, else the default from
L</options>. Dies if C<name> is not a key of L</options>.

=head2 violation

    return $self->violation( $elem, message => '...', fixable => 1 );

Builds a L<Puff::Violation> for C<$elem>, taking the rule, code, line and
column from the rule and the element's location. Arguments:

=over

=item message

The text shown after the code in the report. Default: the rule's
L</summary>.

=item fixable

Optional, default 1. Pass 0 when this particular violation has no fix. It is
always 0 when C<fix_safety> is C<none>.

=back

It dies if the element has no location.

=head1 Puff::Fix object

The C<$fix> passed to C<fix> records edits. An edit replaces a range of
the file's text; offsets are character offsets, with the end exclusive.

=over

=item replace($elem, $text)

Replace the element's text with C<$text>.

=item insert_before($elem, $text)

=item insert_after($elem, $text)

Insert C<$text> at the start or end of the element.

=item delete($elem)

Remove the element's text.

=item replace_range($start, $end, $text)

Replace the offsets C<[$start, $end)> with C<$text>. Use it to change part
of an element. Find offsets with C<< $fix->source->start_of($elem) >> and
C<< $fix->source->end_of($elem) >>.

=item source

The L<Puff::Source> for the text being fixed.

=item Puff::Fix->decline($why)

Declines the fix by dying with a C<Puff::Fix::Decline>. Use it from deep
inside your own helper code, where returning false is awkward.

=back

C<replace>, C<insert_before>, C<insert_after> and C<delete> call
C<< Puff::Fix->decline >> if the element is or contains a
C<PPI::Token::HereDoc> (the body of a here-document is not part of the
element's text), so the rule declines. C<replace_range> does no such
check.

All the edits recorded in one C<fix> call are applied together or not at
all.

=head1 Puff::Violation object

C<check> returns these; C<fix> receives one. Methods: C<rule>, C<code>,
C<element> (the PPI element), C<line> and C<column> (1-based, in
characters), C<message>, C<fixable>, and C<file>.

=head1 SEE ALSO

L<Puff::Fix>, L<Puff::Violation>, L<Puff::PPIUtil> (C<is_builtin_call>,
C<call_args>), L<PPI>.

=cut
