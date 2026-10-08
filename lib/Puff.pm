package Puff;

use v5.36;

our $VERSION = '0.000001';

1;

# ABSTRACT: A Perl linter and fixer, inspired by ruff

__END__

=pod

=head1 NAME

Puff - A Perl linter and fixer, inspired by ruff

=head1 SYNOPSIS

    puff check lib/
    puff check --fix --unsafe-fixes lib/
    puff rules
    puff rule S002

=head1 DESCRIPTION

puff parses Perl with L<PPI>, runs a set of rules with short, stable codes
and can automatically fix many of the problems it finds. See F<README.md>
and L<Puff::Rule> for writing your own rules.

=cut
