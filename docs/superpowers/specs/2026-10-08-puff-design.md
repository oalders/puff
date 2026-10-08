# puff — design

Date: 2026-10-08
Status: approved in conversation; revised after a spec review and pushback
(see `paad/pushback-reviews/2026-10-08-puff-design-pushback.md`)

## Purpose

`puff` is a Perl linter **and fixer**, inspired by Python's ruff. Every
rule has a short, stable code; rules can carry an automatic fix; fixes are
classified as safe or unsafe; and adding a rule takes one small module plus
a pair of fixture files.

It starts with security rules. Speed in ruff's sense is out of reach (PPI is
the bottleneck), so puff gets its speed from the workflow: parse each file
once and walk the tree once. A cache and parallel workers can come later.

## Non-goals for the MVP

- Formatting (perltidy and precious already do this).
- Running existing Perl::Critic policies. The rule API stays close to
  Perl::Critic's (`applies_to` / `violates` becomes `applies_to` / `check`)
  so compatibility can be added later.
- Cache, parallel workers, `--add-noqa`, SARIF and GitHub output, LSP,
  `## no critic`, reporting unused suppressions, `per-file-ignores`,
  searching parent directories for the config file, detecting Perl files
  with no extension by their shebang line.

## Platform

- Requires Perl 5.36 or newer. Code uses `use v5.36` (strict, warnings and
  signatures). Plain Perl OO; no Moo.
- Runtime dependencies: PPI, App::Cmd, Module::Pluggable, Module::Runtime,
  TOML::Tiny, Path::Tiny, Text::Diff, JSON::PP. Tests use Test2::V0.
  Dependencies are listed in `cpanfile` and installed for development into
  `./local` (`cpanm -L local --installdeps .`).
- Packaged with Dist::Zilla.

## Architecture

```
puff check [paths] --fix
  Puff::CLI (App::Cmd)  ->  Puff::Config  (.puff.toml + flags)
        |
  Puff::Runner      finds files, runs the engine on each one, collects results
        |
  Puff::Engine      one file:
     load:   Puff::Source  (raw bytes -> decoded text, line-start table)
     lint:   PPI::Document -> walk once, send each element to the rules whose
             applies_to matches it -> Violations -> drop suppressed ones
     fix:    for each fixable violation allowed by the current mode:
                rule->fix($violation, Puff::Fix) -> a group of edits
             Puff::Edits: order, drop conflicting fixes, apply
             re-parse, re-lint, repeat while the text changes (max 10 passes)
        |
  Puff::Reporter::{Text,JSON}
```

### Units

| Unit | Responsibility |
|---|---|
| `Puff::Source` | Reads a file. Strips and remembers a UTF-8 BOM. Decodes as UTF-8 (strict); if that fails, decodes as Latin-1. Records whether the text contains a carriage return (CRLF or lone CR line endings). Builds a line-start table (character offset where each line starts) from the decoded text. Converts PPI locations into character offsets: `line_start[line] + rowchar - 1`. Writes text back using the original encoding and BOM, atomically (temp file in the same directory, then rename), keeping file permissions; a symlink is resolved first so its target is replaced, not the link. Encoding is strict: a character the original encoding cannot hold is an error, never a `?`. |
| `Puff::Rule` | Base class for rules. |
| `Puff::Rules` | Loads rules (`Puff::Rule::*` on @INC, plus every `.pm` under each configured `rule-paths` directory), checks codes, selects rules. |
| `Puff::Violation` | rule, element, file, line, column, message. Line and column are 1-based, columns counted in characters (`location->[0]`, `location->[1]`). |
| `Puff::Fix` | Rule-facing helpers: `replace($elem, $text)`, `insert_before($elem, $text)`, `insert_after($elem, $text)`, `delete($elem)`, plus `replace_range($start, $end, $text)` for rewriting inside a single token (for example inside `<FH>`). An element's range runs from the start of its first token to the end of its last token; end = token start + `length($token->content)`. Calling a helper on an element that contains a `PPI::Token::HereDoc` throws an exception, which counts as declining the fix. |
| `Puff::Edits` | Pure text manipulation. Input: the text and a list of fixes, each a list of `{start, end, text}`. See "Applying fixes". |
| `Puff::Suppressions` | Parses suppression comments from the PPI document. |
| `Puff::Engine` | Lints and fixes one file. |
| `Puff::Runner` | Finds files under the given paths, skips `exclude` matches, runs the engine, and works out the exit code. |
| `Puff::Config` | Reads `./.puff.toml` from the current directory, or the file given with `--config`; ignores config entirely with `--no-config`. Merges config with command-line flags. |
| `Puff::Reporter::Text`, `Puff::Reporter::JSON` | Turn results into output. |

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

sub check ($self, $elem, $doc) { ...; return $self->violation($elem, message => '...') }
sub fix   ($self, $violation, $fix) { ...; return 1 }   # return false to decline
```

- `check` returns a list (zero or more violations). `$doc` is the whole
  document, so a rule can look at more than the element it was given.
- `fix` may decline for an individual violation by returning false,
  recording no edits, or calling `Puff::Fix->decline($why)` (which dies
  with a `Puff::Fix::Decline`); any edits it already recorded are thrown
  away. The `Puff::Fix` helpers that take an element decline this way when
  the element contains a heredoc. Any other exception from `fix` is an
  error (see "Applying fixes"). A violation from a
  rule whose `fix_safety` is `none` has no fix.
- `$self->option('name')` returns the configured value, falling back to the
  default.
- `violation(..., fixable => 0)` marks one violation as having no fix even
  though its rule has fixes (for example `CORE::rand`), so that reports
  don't promise a fix that will be declined.

### Codes

- A code is one or more uppercase letters followed by three digits
  (`/\A[A-Z]+[0-9]{3}\z/`). puff uses `S` (security) and, later, `B`
  (bugs) and `M` (modernize); third-party rules should use a prefix of two
  or more letters (`ACME001`). This is a convention for now, not enforced.
- An invalid code, or two rules with the same code, is a fatal startup
  error (exit 2) that names the modules involved.
- `--select` and `--ignore` match by prefix: `S` matches `S001`; `S00`
  matches `S001` through `S009`. A rule runs if it matches `select` (or
  `extend-select`) and does not match `ignore`.
- **`P001`** ("suppression comment must list codes") is built into the
  engine rather than being a rule class. It is always on, cannot be
  selected, ignored or suppressed, has no fix, and is listed by
  `puff rules`.

## Suppressions

- `# puff: ignore S001, S002` suppresses those codes for violations
  reported on that line. Codes are separated by commas, with optional
  spaces. The comment may be on its own or at the end of a line of code.
- `# puff: ignore-file S001` anywhere in the file suppresses those codes for
  the whole file.
- A suppression code may be a prefix, as in `--ignore`.
- A bare `# puff: ignore` or `# puff: ignore-file` (with no codes)
  suppresses nothing and is reported as `P001`.
- Suppressed violations are neither reported nor fixed.

## Config (`.puff.toml`)

```toml
select        = ["S"]          # default ["S"]
extend-select = []
ignore        = []
rule-paths    = ["xt/puff-rules"]
exclude       = ["local", "blib", ".build", ".git"]   # path-segment names or relative path prefixes
unsafe-fixes  = false

[rules.S001]
# rule options (no MVP rule has any)
```

- `exclude` entries are compared against the path relative to the
  directory being searched: an entry with no `/` matches any path segment
  with that name; an entry containing `/` matches a path prefix. The
  defaults above always apply.
- **`rule-paths` runs code.** Running puff in a repository with a
  `.puff.toml` that sets `rule-paths` loads and executes the Perl modules
  in that directory, just as running its tests would. `--no-config` turns
  this off. The README says so.
- Unknown keys are a fatal config error (exit 2), so typos don't silently
  do nothing.

Flags override the file: `--select`, `--extend-select`, `--ignore` (each
comma-separated and repeatable), `--fix`, `--unsafe-fixes`, `--diff`,
`--output-format text|json`, `--config PATH`, `--no-config`.

Files checked: `*.pl`, `*.pm`, `*.t`, `*.psgi`, found by recursing into
directories. A file named explicitly on the command line is always checked,
whatever its name.

## Commands

- `puff check [paths...]`. Defaults to `.`.
- `puff rule CODE`. Prints the code, summary, fix safety and explanation.
- `puff rules`. Lists every loaded rule (code, fix safety, summary), plus
  P001.

### Fix modes

- `--fix` applies **safe** fixes. `--fix --unsafe-fixes` (or
  `unsafe-fixes = true` in config) applies safe and unsafe fixes.
- **All three MVP rules are unsafe**, so plain `--fix` changes nothing for
  them, and the output says how many unsafe fixes are available. This is
  deliberate: security fixes change behaviour.
- `--diff` works out the same fixes as `--fix` but writes nothing; it
  prints a unified diff per file. `--diff` together with `--fix` means
  `--diff`.

### Exit codes

- 2: usage, config, rule-loading or internal error; a file that can't be
  read or parsed; or a fix that failed (the result didn't parse, or the
  pass cap was hit). The failing file is left unchanged and the error is
  reported; other files are still processed. **2 takes priority over 1.**
- 1: violations remain (after fixing, if fixing), or `--diff` would change
  something.
- 0: otherwise.

## Applying fixes

1. Work out the fixes for every unsuppressed violation whose rule is
   fixable in the current mode and which isn't marked `fixable => 0`.
   A `fix` that returns false, records no edits or throws
   `Puff::Fix::Decline` is a silent decline. A `fix` that dies with
   anything else is an error: abandon fixing this file, keep the original
   text and report `rule CODE fix failed: MESSAGE` (exit 2).
2. Sort the fixes by the start offset of their earliest edit, then by rule
   code, then by line.
3. Go through them in that order. A fix is **accepted** if none of its
   edits conflicts with an edit already accepted, and **deferred** (to the
   next pass) otherwise; it is also deferred when two of its own edits
   conflict with each other. All edits of a fix are accepted together, or
   none are.
   - Edits are half-open ranges `[start, end)`. Two replacements or
     deletions conflict if their ranges overlap. An insertion at X
     (start = end = X) conflicts with a replacement `[s, e)` when s < X < e.
   - An edit identical to an accepted one (same start, end and text) does
     not conflict; it is dropped. This is how several S001 violations
     share one inserted `use` line.
   - Insertions at the same offset are applied in the order they were
     accepted.
4. Apply the accepted edits from the end of the text backwards.
5. Re-parse. If `PPI::Document->new` returns undef, abandon fixing this
   file: keep the original text and report an error (exit 2).
6. Re-lint and repeat while the text changed during the pass. If 10 passes
   go by and the text is still changing, abandon fixing, keep the original
   text and report an error. puff never runs `perl -c` (it would execute
   `BEGIN` blocks).
7. Write the file once, at the end, only if the text changed.

**CRLF files** (and any file containing a carriage return, such as lone CR
line endings) are linted normally, but puff doesn't fix them in the MVP:
their violations are reported with `fixable` 0, so no fix marker is shown.
When fixes were asked for, the report says that they were skipped because
of the line endings.

## Output

Text (default), one line per violation, sorted by file, line and column:

```
lib/Foo.pm:12:5: S002 Use three-argument open [*]
```

`[*]` marks a violation that would be fixed with the current settings;
`[**]` marks one that has an unsafe fix which is not enabled. At the end:
`Found N violations.` plus, when relevant, `M fixable with --fix` and
`K more fixable with --unsafe-fixes`. With `--fix`, also print
`Fixed N violations in M files.`

JSON: an array of `{code, message, file, line, column, fix: {safety,
available, applied}}` for violations that remain. Errors go to STDERR.

## MVP rules

### S001 `rand`/`srand` is not cryptographically secure

**Detection.** A `PPI::Token::Word` with content `rand`, `srand`,
`CORE::rand` or `CORE::srand` is a call to the built-in unless any of the
following holds:
- the previous significant sibling is the operator `->` (a method call);
- the next significant sibling is the operator `=>` (a hash key);
- it is the name in a `sub` declaration;
- its parent is a `PPI::Statement::Expression` directly inside a
  `PPI::Structure::Subscript` and it is the only significant child of that
  expression (`$h{rand}`);
- it is part of a `package`, `use` or `no` statement.

**Skip.** If the file contains `use Math::Random::Secure` whose import
list includes `rand` (a `qw(...)` list or a quoted string), plain `rand`
calls are not reported at all.

**Fix (unsafe).** Applies only to plain `rand`. Insert the line
`use Math::Random::Secure qw(rand);` where it will be compiled before the
first `rand` call:
- Find the top-level statement (a direct child of the document) that
  contains the first `rand` call: call it T.
- The file must have no `package` statement, or exactly one `package NAME;`
  statement (not the block form) that comes before T. Otherwise, decline.
- Insert after the last top-level `use` or `no` statement that comes before
  T and after the package statement, if there is one. If there's no such
  statement, insert after the package statement; if there's no package
  statement either, insert before T.
- The inserted text is `"\nuse Math::Random::Secure qw(rand);"` when
  inserting after a statement, and `"use Math::Random::Secure qw(rand);\n"`
  when inserting before T. Every `rand` violation produces this same edit,
  so it is applied once.
- `srand`, `CORE::rand` and `CORE::srand` are reported with `fixable => 0`.
  (An import can't override `CORE::rand`, and seeding a secure generator
  has no meaningful fix.)

### S002 Two-argument `open`

**Detection.** A `PPI::Token::Word` with content `open` that is a call to
the built-in (same exclusions as S001: method, hash key, sub name,
subscript). Its arguments are:
- if the next significant sibling is a `PPI::Structure::List`: the
  children of the list's single expression;
- otherwise: the significant siblings that follow it, up to (not
  including) the first `;`, the low-precedence operators `or`, `and`,
  `xor`, `not`, or a statement-modifier word (`if`, `unless`, `while`,
  `until`, `for`, `foreach`).

Split the arguments on top-level `,` and `=>` operators. Nested structures
(lists, blocks, subscripts) count as part of one argument. The call is a
violation if there are exactly 2 arguments.

**Fix (unsafe).** Let ARG be the second argument.
1. ARG is a single `PPI::Token::Quote::Single` or `PPI::Token::Quote::Double`
   (`'...'` or `"..."`; other quote styles decline). Let S be its string
   contents.
   - Decline if S is empty, starts with `|` or `&`, ends with `|`, is `-`
     or `>-`, or (double quotes only) starts with `$` or `@` after leading
     whitespace (the mode could be inside the variable).
   - If S matches `^\s*(\+?(?:>>|<|>))\s*(.*?)\s*$` with a non-empty
     filename part F: the mode is `$1`. Replace ARG with `'MODE', F'`,
     where F' is the bare variable if F is exactly one simple scalar such as
     `$file` (double quotes only), and F requoted with ARG's original quote
     characters otherwise.
   - Otherwise, if S has no leading or trailing whitespace: replace ARG
     with `'<', ARG`.
   - Otherwise decline.
2. ARG is a single `PPI::Token::Symbol` starting with `$` that isn't
   followed by a subscript or `->`: replace ARG with `'<', ARG`.
3. Anything else: decline.

The explanation documents the behaviour changes this fix makes: two-arg
open trims whitespace around the filename and three-arg open does not; a
filename containing a mode or pipe is now taken literally (which is the
point); a scalar holding a reference becomes an in-memory open.

### S003 Bareword filehandle

**Detection.** A call to the built-in `open`, `opendir`, `sysopen` or
`socket` (arguments found as in S002) whose first argument is a single
`PPI::Token::Word` other than `STDIN`, `STDOUT`, `STDERR`, `DATA`, `ARGV`,
`ARGVOUT` or `_` (compared case-sensitively), and other than `my`, `our`,
`local` or `state`.

**Fix (unsafe).** Applies to `open`, `opendir` and `sysopen` (not
`socket`). Let NAME be the bareword and B the parent of the open
statement. The fix is applied only when all of the following hold;
otherwise it declines:
- The open is a plain `PPI::Statement` (not a compound statement, so not
  inside an `if`/`unless`/`while` condition) and B is a
  `PPI::Structure::Block` or the document.
- This is the only open/opendir/sysopen in the file with this NAME.
- Every other `PPI::Token::Word` with content NAME, and every
  `PPI::Token::QuoteLike::Readline` whose content is `<NAME>`, is inside B,
  comes after the open, and is one of these recognised uses:
  - `<NAME>`, rewritten to `<$var>` with `replace_range` inside the token;
  - the first token after `print`, `printf` or `say`, when it isn't
    followed by a `,` or `(`: rewritten to `{$var}`;
  - `NAME` as the only content of a block directly after `print`, `printf`
    or `say`, as in `print {NAME} ...`: rewritten to `$var`;
  - the first argument (as in S002) of `close`, `eof`, `binmode`, `fileno`,
    `flock`, `seek`, `tell`, `truncate`, `read`, `sysread`, `syswrite`,
    `readdir`, `closedir`, `rewinddir`, `telldir` or `seekdir`: rewritten
    to `$var`.
- NAME doesn't appear as `*NAME` or `\*NAME` anywhere in the file.

The variable name is `lc NAME`, unless the decoded file text already
matches `[\$\@\%]\{?NAME\b` for that name (in code or inside strings), in
which case it is `lc(NAME) . '_fh'`, and then `_fh2`, `_fh3` and so on
until the name is free. The open's first argument is rewritten to
`my $var`.

S002 and S003 change different tokens of the same open, so both fixes are
usually applied in the same pass.

## Testing

- Unit tests for `Source` (round trips and offsets for heredocs, POD,
  `__END__`/`__DATA__`, UTF-8 with multi-byte characters before a target,
  Latin-1, BOM, CRLF), `Edits` (ordering, conflicts, identical-edit
  dropping, insertions at the same offset), `Suppressions`, `Config`, and
  rule selection.
- Each rule has fixture files under `t/corpus/<CODE>/`: `<name>.pl` and
  optionally `<name>.fixed.pl`. Lines that should be reported carry an
  `# expect: CODE` comment. If `<name>.fixed.pl` exists, running the fixer
  with unsafe fixes must produce exactly that text; if it doesn't, the
  fixer must leave the file unchanged. A shared harness
  (`t/lib/PuffTest.pm`, with a `run_corpus` function) does this and is
  available to rule authors. The `# expect:` comments stay in the fixed
  file; the harness strips them before comparing violations in the fixed
  output. After fixing, the fixed text is linted again: it must have no
  violations from the rule being tested, apart from ones marked
  `fixable => 0`.
- An end-to-end test runs `bin/puff` on a copy of the fixtures in a
  temporary directory, checking output, exit codes, `--diff`, `--fix`
  without unsafe fixes changing nothing, and `--fix --unsafe-fixes`
  rewriting files.
