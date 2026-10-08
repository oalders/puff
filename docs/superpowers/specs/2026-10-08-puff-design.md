# puff — design

Date: 2026-10-08
Status: approved in conversation, MVP to be built

## Purpose

`puff` is a Perl linter **and fixer**, inspired by Python's ruff. Every
rule has a short, stable code; rules can carry an automatic fix; fixes are
classified as safe or unsafe; and anyone can add rules, either from CPAN or
from a directory in their own project.

It starts with security rules. Speed in ruff's sense is out of reach (PPI is
the bottleneck), so puff gets its speed from the workflow: parse each file
once, walk the tree once, and later add a cache and parallel workers.

## Non-goals for the MVP

- Formatting (perltidy and precious already do this).
- Running existing Perl::Critic policies. The rule API is kept close to
  Perl::Critic's (`applies_to` / `violates` becomes `applies_to` / `check`)
  so compatibility can be added later.
- Cache, parallel workers, `--add-noqa`, SARIF output, an LSP server,
  honouring `## no critic`, reporting unused suppressions.

## Platform

- Requires Perl 5.36 or newer. Code uses `use v5.36` (strict, warnings and
  signatures).
- Plain Perl OO; no Moo.
- Dependencies: PPI, App::Cmd, Module::Pluggable, Module::Runtime,
  TOML::Tiny, Path::Tiny, Text::Diff. Tests use Test2::V0.
- Packaged with Dist::Zilla.

## Architecture

```
puff check [paths] --fix
  Puff::CLI (App::Cmd)  ->  Puff::Config  (.puff.toml + flags)
        |
  Puff::Runner      finds files, runs the engine on each one
        |
  Puff::Engine
     lint_file:  read -> PPI::Document -> SourceMap -> walk once,
                 send each element to the rules whose applies_to matches it
                 -> Violations -> drop suppressed ones
     fix_file:   for each fixable violation allowed by the current mode
                 (safe, or safe+unsafe):
                    rule->fix($violation, Puff::Fix)  -> byte-range edits
                 Puff::Edits: sort, drop overlapping edits, apply
                 re-parse, re-lint, repeat until nothing changes (max 10 passes)
                 if the result doesn't parse cleanly or the cap is hit:
                 keep the original file and report an error
        |
  Puff::Reporter::{Text,JSON,GitHub}
```

### Units

| Unit | Responsibility |
|---|---|
| `Puff::Rule` | Base class for rules. |
| `Puff::Rules` | Finds rules (`Puff::Rule::*` on @INC, plus `.pm` files under each configured `rule-paths` directory), checks codes are unique, selects rules by code prefix. |
| `Puff::Violation` | rule, element, line, column, message, file. Holds a reference to the element. |
| `Puff::SourceMap` | Maps between PPI elements and byte offsets, worked out by walking the tokens of the PPI document and adding up their lengths. |
| `Puff::Fix` | Helpers for rules: `replace($elem, $text)`, `insert_before($elem, $text)`, `insert_after($elem, $text)`, `delete($elem)`. Each call records a `{start, end, text}` edit. A fix is all-or-nothing: either every edit for a violation is applied, or none. |
| `Puff::Edits` | Pure text. Given the source and a list of *fixes* (each a group of edits), applies the fixes whose edits don't overlap an earlier accepted fix, from last to first. Inserts at the same offset are allowed and keep the order they were recorded in. |
| `Puff::Suppressions` | Parses `# puff: ignore CODE[,CODE]` (applies to that line) and `# puff: ignore-file CODE[,CODE]` (applies to the whole file). |
| `Puff::Engine` | Lints and fixes one file. |
| `Puff::Runner` | Finds files and runs the engine over them, one at a time for now. |
| `Puff::Config` | Finds `.puff.toml` by searching upward from the current directory, stopping at the directory containing `.git`; merges it with command-line flags. |
| `Puff::Reporter::*` | Turns results into output. |

## Rule API

```perl
package Puff::Rule::Security::TwoArgOpen;
use v5.36;
use parent 'Puff::Rule';

sub code        { 'S002' }
sub summary     { 'Use three-argument open' }
sub explanation { "..." }               # text shown by `puff rule S002`
sub applies_to  { 'PPI::Token::Word' }  # a class name or a list of them
sub fix_safety  { 'unsafe' }            # safe | unsafe | none
sub options     { {} }                  # option name => default

sub check ($self, $elem, $doc) { ... return $self->violation($elem, message => '...') }
sub fix   ($self, $violation, $fix) { ...; return 1 }   # return 0 to decline
```

- `check` returns a list (zero or more violations).
- `fix` may decline for an individual violation by returning false; any edits
  it already recorded are thrown away.
- `$self->option('name')` returns the configured value, falling back to the
  default.
- Rules may also implement `check_document($self, $doc)` for checks that look
  at the whole file. It is called once per document, and its violations go
  through the same suppression and fixing as the rest.

### Codes

- Single-letter prefixes belong to puff itself: `S` security, `B` bugs,
  `M` modernize. A code is the prefix letters followed by three digits.
- Third-party rules use a prefix of two or more letters (`ACME001`).
- Two rules with the same code are a fatal startup error that names both
  modules.
- `--select` and `--ignore` match by prefix: `S` matches `S001`; `S00`
  matches `S001` through `S009`.

## Suppressions

- `# puff: ignore S001,S002` suppresses those codes on the line where the
  comment appears. For a statement that spans several lines, the comment
  goes on the line where the violation is reported.
- `# puff: ignore-file S001` anywhere in the file suppresses those codes for
  the whole file.
- A bare `# puff: ignore` (with no codes) suppresses nothing and is itself
  reported as **`P001`** ("suppression comment must list codes").
  `P` is puff's meta prefix and is always enabled.
- Suppressed violations are never fixed.

## Config (`.puff.toml`)

```toml
select       = ["S"]          # default ["S"]
ignore       = []
rule-paths   = ["xt/puff-rules"]
exclude      = ["local/", "blib/", ".build/", ".git/"]
unsafe-fixes = false

[per-file-ignores]
"t/**" = ["S001"]

[rules.S001]
# rule options
```

Flags override the file: `--select`, `--extend-select`, `--ignore`,
`--fix`, `--unsafe-fixes`, `--diff`, `--output-format text|json|github`,
`--config PATH`, `--no-config`.

Which files are checked: `*.pl`, `*.pm`, `*.t`, `*.psgi`, and files with no
extension whose first line is a shebang mentioning `perl`. A file named
explicitly on the command line is always checked, whatever its name.

## Commands

- `puff check [paths...]`. Defaults to `.`.
- `puff rule CODE`. Prints the summary, fix safety and explanation.
- `puff rules`. Lists every rule (code, fix safety, summary).

### Exit codes

- 0: no violations remain (after fixing, if `--fix` was given).
- 1: violations remain.
- 2: usage, config or internal error (including a parse error in a file
  being linted, a fix that produced code that doesn't parse, or the pass
  cap being hit).

### `--diff`

Prints a unified diff of what `--fix` would change, without writing
anything. Exit code is 1 if there would be changes, 0 otherwise. `--diff`
turns fixing on.

## Output

Text (default):

```
lib/Foo.pm:12:5: S002 Use three-argument open [*]
```

`[*]` marks a fix that `--fix` would apply; `[**]` marks one that needs
`--unsafe-fixes`. At the end: a count of violations, and of fixes
available with and without unsafe fixes.

JSON: an array of `{code, message, file, line, column, fix: {safety,
applicable}}`.

GitHub: `::error file=...,line=...,col=...,title=S002::Use three-argument open`.

## MVP rules

### S001 `rand`/`srand` is not cryptographically secure

- Flags every call to the built-in `rand` or `srand`, meaning a
  `PPI::Token::Word` that is `rand`, `srand`, `CORE::rand` or `CORE::srand`
  and is not a method name (`->rand`), a hash key (`{rand}`, `rand =>`),
  a sub name (`sub rand`) or part of a package name.
- Fix: **unsafe**. For `rand`, insert
  `use Math::Random::Secure qw(rand);` after the file's last top-level
  `use` statement (or at the top of the file, after the shebang, if there
  isn't one) and leave the calls alone. The import goes in at most once,
  and if the file already imports Math::Random::Secure's `rand`, `rand`
  calls aren't reported at all. For `srand`, there is no fix (the violation
  is still reported).
- When a file has several `rand` violations, they all produce the same
  insertion. Edits identical to one already accepted are dropped rather
  than counted as conflicts.

### S002 Two-argument `open`

- Flags `open` (the built-in function call, not a method) with exactly two
  arguments.
- Fix: **unsafe**. When the second argument is a string literal or
  interpolated string whose contents start with a mode (`<`, `>`, `>>`,
  `+<`, `+>`, `+>>`) followed by optional whitespace and then the rest,
  rewrite it as `MODE, REST`, where REST is the remaining text kept as a
  string of the same quote style; if REST is a single variable such as
  `$file`, emit the bare variable. When the second argument is a bare
  scalar or an expression with no mode, rewrite it as `'<', ARG`. Decline
  (no fix) if the string starts with `|` or ends with `|` (pipe opens), is
  `-` (STDIN or STDOUT), or uses `&` (duplicating a filehandle).

### S003 Bareword filehandle

- Flags `open`, `opendir`, `sysopen` and `socket` whose first argument is a
  bareword other than `STDIN`, `STDOUT`, `STDERR`, `DATA`, `ARGV`,
  `ARGVOUT` or `_`.
- Fix: **unsafe**. Rename `FH` to `my $fh` in the open, and `FH` to `$fh`
  everywhere else in the **same file** where it is clearly used as a
  filehandle: `<FH>`, `print FH`, `printf FH`, `say FH`, and as the first
  argument of `close`, `eof`, `binmode`, `seek`, `tell`, `read`, `sysread`,
  `syswrite`, `fileno`, `flock`, `truncate`, `readdir`, `closedir`,
  `rewinddir`, `select` (one argument) and `-X` file tests. Handle names
  are lower-cased (`$fh` for `FH`, `$in` for `IN`); if that name is
  already used anywhere in the file, add a `_fh` suffix and then numbers
  until the name is free.
- Decline the whole fix if the handle name appears anywhere else that the
  fix doesn't understand (for example `*FH`, `\*FH`, being passed to a sub,
  or an open for the same name in a different scope) or if the opens and
  uses aren't all inside the same sub or block. When it's not certain, it
  declines.
- `print FH` and `print {FH}` both become `print {$fh}`.
- S002 and S003 often hit the same `open` statement; the fix loop handles
  that, with overlapping fixes left for the next pass.

## Testing

- Unit tests for `Edits`, `SourceMap`, `Suppressions`, `Config` and rule
  selection.
- Each rule has fixture pairs under `t/corpus/<CODE>/` (`<name>.pl` and
  `<name>.fixed.pl`; when only `<name>.pl` exists, the rule must not fix
  it) plus expected violations given in the fixture itself, as
  `# expect: S002` comments on lines that should be reported. A shared test
  harness (`t/lib/PuffTest.pm`) runs both lint and fix over each pair.
  Rule authors can use the same harness.
- An end-to-end test runs the `puff` script on a temporary directory and
  checks its output and exit codes.
- After a successful fix, every fixed file in the corpus is checked to make
  sure it still compiles (`perl -c`), for files that don't depend on
  modules that aren't installed.
