# puff

puff is a linter and fixer for Perl, inspired by Python's ruff. Each rule has
a short stable code (such as `S002`), can carry an automatic fix, and says how
safe that fix is. Adding a rule takes one small module and a few fixture
files. It parses files with [PPI](https://metacpan.org/pod/PPI) and never
runs the code it checks.

By default puff runs the security (`S`) and likely-bug (`B`) rules; the
style rules are opt-in. puff does not format code; use perltidy for that.

## Install

puff needs Perl 5.36 or newer.

    cpanm --installdeps .

To keep the dependencies inside the checkout, use
`cpanm -L local --installdeps .` and run puff with
`perl -Ilib -Ilocal/lib/perl5 bin/puff`.

## Usage

    puff check [paths...]        lint files and directories (default: .)
    puff rules                   list every rule
    puff rule CODE               explain one rule

Directories are searched recursively for `*.pl`, `*.pm`, `*.t` and `*.psgi`
files, and for files with no `.` in their name (such as `bin/tool`) whose
first line is a Perl shebang: `#!` and a path whose last part starts with
`perl` (`#!/usr/bin/perl -w`), or `#!/usr/bin/env perl` (env options such as
`-S` allowed). Only the first 256 bytes are read; unreadable and binary files
are skipped silently. A file named on the command line is always checked.
Symlinked directories are not followed.

Lint a project:

    $ puff check
    lib/Demo.pm:5:5: S002 Use three-argument open [**]
    lib/Demo.pm:5:5: S003 Bareword filehandle FH; use a lexical filehandle [**]
    Found 2 violations (checked 1 file).
    2 more fixable with --unsafe-fixes

Each line is `file:line:column: CODE message`, sorted by file, line and
column. A marker at the end of the line says what a fix would do:

- `[*]`: `--fix` will fix it with the current settings.
- `[**]`: it has an unsafe fix that is not enabled. Add `--unsafe-fixes`.
- no marker: no fix is offered for this violation.

The `Found` line counts the violations and the files checked; to see which
files those are, run `puff check --show-files`. On a terminal, a run that
takes more than half a second shows a spinner and a `Checking N/M files`
counter on STDERR while it works.

To see which rules fire most and which of them can be fixed, use
`--statistics`. It prints one line per rule instead of one per violation:

    $ puff check --statistics
    29  S002  [**]  Use three-argument open (9 fixable)
    29  S003  [**]  Use a lexical filehandle instead of a bareword (3 fixable)
     2  S001  [**]  rand/srand is not cryptographically secure
    Found 60 violations (checked 4 files).
    14 more fixable with --unsafe-fixes

### Options for `check`

| Option | Meaning |
| --- | --- |
| `--select CODES` | Enable rules whose code starts with one of these prefixes. Replaces the configured `select`. |
| `--extend-select CODES` | Enable these rules as well. |
| `--ignore CODES` | Disable these rules. |
| `--fix` | Write safe fixes to the files. |
| `--unsafe-fixes` | Also apply unsafe fixes (with `--fix` or `--diff`). `--no-unsafe-fixes` turns off `unsafe-fixes = true` from the config. |
| `--diff` | Print the fixes as a unified diff and write nothing. Wins over `--fix`. |
| `--output-format text\|json\|jsonl` | Output format; default `text`. `jsonl` streams JSON Lines (see below). |
| `--show-files` | List the files that would be checked, one per line, and check nothing. Plain paths, and `--statistics` does not apply, whatever `--output-format` says. |
| `--statistics` | Print one line per rule instead of one per violation: the count, the fix marker, the rule's summary, and `(N fixable)` when only some can be fixed. Most violations first. Only with `--output-format text` (the default); with `json` or `jsonl` it is a usage error. |
| `--config PATH` | Read this config file instead of `./.puff.toml`. |
| `--no-config` | Ignore config files. |

`CODES` is a comma-separated list, and the option can be repeated. A code can
be a prefix: `S` means every `S` rule, `S00` means `S001` to `S009`. `ALL`
means every rule, so `puff check --select ALL --fix --unsafe-fixes` runs every
rule and applies every fix. A
`select` or `extend-select` entry that matches no rule is an error
(`Unknown rule selector: X`, exit `2`), so a typo does not silently turn
rules off. An `ignore` entry that matches nothing is allowed.

### Exit codes

- `0`: no violations remain.
- `1`: violations remain (after fixing, if you asked for fixes), or `--diff`
  would change something.
- `2`: a usage, config or rule-loading error; a file that cannot be read or
  parsed; or a fix that failed. The failing file is left unchanged, the
  error goes to STDERR and other files are still processed. `2` wins over `1`.

### JSON output

`--output-format json` prints an array with one object per remaining
violation:

    $ puff check --output-format json
    [
       {
          "code" : "S002",
          "column" : 5,
          "file" : "lib/Demo.pm",
          "fix" : {
             "applied" : false,
             "available" : true,
             "safety" : "unsafe"
          },
          "line" : 5,
          "message" : "Use three-argument open"
       }
    ]

`fix.safety` is the rule's fix safety, `fix.available` says whether a fix is
offered for this violation, and `fix.applied` is always `false` because only
violations that remain are listed. Errors still go to STDERR as text.
`--diff` wins over `--output-format json` and prints the plain diff.

### JSON Lines output

`--output-format jsonl` streams one JSON object per line as each file is
checked, so a tool can show progress or start work before the run ends:

    $ puff check --output-format jsonl lib missing.pl
    {"total":2,"type":"start"}
    {"error":null,"file":"lib/Demo.pm","fixed":0,"fixes_skipped":null,"type":"file","violations":[{"code":"S002",...}]}
    {"error":"No such file or directory","file":"missing.pl","fixed":0,"fixes_skipped":null,"type":"file","violations":[]}
    {"exit_code":2,"type":"done"}

Each event is one line ending in `\n`, and the output is pure ASCII: non-ASCII
characters are `\u` escapes, so U+2028, U+2029 and U+0085 never appear raw for
a Unicode-aware line splitter to break on. `start` comes first, with the number
of files to check, unless puff fails before the files are found: then the
stream is just `done` with an `error`. Each `file` event follows in the order
the files are checked: `violations` holds the same objects as the JSON output,
`error` is the file's error or `null` (errors are not printed to STDERR),
`fixes_skipped` is why fixes were not applied (such as CRLF line endings) or
`null` (also not printed to STDERR), and `fixed` is the number of fixes `--fix`
wrote to the file (always 0 with `--diff`). With `--diff`, each `file` event
also has `diff`: the unified diff, or `null` when nothing would change. `done`
is always the last line of any run that does not crash outright, with the exit
code; if puff dies part way it still prints `done` with `"exit_code":2` and an
`error`. A stream that ends without `done` means puff was killed or aborted:
treat it as a failure. More event types and keys may be added later, so ignore
any you do not know. File names, messages, errors and diffs come from the
linted files: treat them as untrusted data.

## Fix safety

Every fix is either safe or unsafe.

- A safe fix does not change what the program does.
- An unsafe fix can change behaviour, so you should review it.

`puff check --fix` applies safe fixes only. `puff check --fix --unsafe-fixes`
(or `unsafe-fixes = true` in the config) applies both. The default security
rules are all unsafe, so plain `--fix` changes nothing for them:

    $ puff check --fix
    lib/Demo.pm:5:5: S002 Use three-argument open [**]
    lib/Demo.pm:5:5: S003 Bareword filehandle FH; use a lexical filehandle [**]
    Found 2 violations (checked 1 file).
    2 more fixable with --unsafe-fixes
    Fixed 0 violations in 0 files.

Look at what would change before writing anything:

    $ puff check --diff --unsafe-fixes
    --- a/lib/Demo.pm
    +++ b/lib/Demo.pm
    @@ -2,9 +2,9 @@
     use v5.36;
     
     sub load ($file) {
    -    open(FH, "<$file");
    -    my @l = <FH>;
    -    close(FH);
    +    open(my $fh, '<', $file);
    +    my @l = <$fh>;
    +    close($fh);
         return @l;
     }
     
    Would fix 2 violations in 1 file.

The diff goes to STDOUT and the `Would fix` line to STDERR.

How fixes are applied:

- puff computes the fixes for all violations, applies the ones that do not
  overlap, re-parses the file, lints it again and repeats while the text
  changes, up to 10 passes.
- If the fixed text no longer parses, the passes do not converge, or a
  rule's fix fails with an error, the file is left unchanged and puff
  reports an error (exit `2`).
- A file is written once, only if its text changed.
- puff never runs `perl -c` on your code.
- Files containing a carriage return (CRLF or lone CR line endings) are
  linted but not fixed, and their violations are not offered as fixable.
  With `--fix` or `--diff`, puff says so on STDERR.
- A file is written in the encoding it was read in (UTF-8, else Latin-1),
  keeping a BOM. If a fix adds a character that encoding cannot hold, the
  file is left unchanged and puff reports an error.
- The file is replaced atomically (a temporary file in the same directory,
  renamed over it), keeping its permission bits. A symlink is followed: the
  file it points to is replaced and the link stays. Ownership is not kept
  (the new file belongs to whoever runs puff), and a hard link to the old
  file keeps the old text.
- A rule may decline to fix a particular violation (see the table below). It
  is still reported, without a marker.

## Config reference

puff reads `.puff.toml` from the current directory, if there is one. It does
not search parent directories. Unknown keys are an error (exit `2`), so a typo
does not silently do nothing.

    select        = ["S", "B"]
    extend-select = []
    ignore        = []
    rule-paths    = ["xt/puff-rules"]
    exclude       = ["fixtures"]
    unsafe-fixes  = false

    [rules.X001]
    keyword = "FIXME"

| Key | Default | Meaning |
| --- | --- | --- |
| `select` | `["S", "B"]` | Rule codes or prefixes to enable. `ALL` enables every rule. |
| `extend-select` | `[]` | More codes or prefixes to enable. |
| `ignore` | `[]` | Codes or prefixes to disable. Wins over `select`. |
| `rule-paths` | `[]` | Directories of extra rule modules. A relative path is relative to the config file's directory; an absolute path is used as it is. See below. |
| `exclude` | `["/local", "/blib", "/.build", "/.git"]` | Paths to skip when searching directories. Entries you list are added to the defaults. |
| `unsafe-fixes` | `false` | Apply unsafe fixes as well as safe ones. Must be `true` or `false` (not a string or number). |
| `[rules.CODE]` | none | Options for one rule. Unknown option names are an error. A001, B003, B005, B006, M001, S007 and S013 have options; `puff rule CODE` describes them. |

The project root is the directory holding the config file, or the current
directory when there is none. `exclude` entries match whole path segments:

- An entry starting with `/` is anchored to the project root. The defaults
  are anchored, so `/local` skips `./local/...` but `t/local/http.t` is still
  checked. An anchored entry does not apply to a directory you name
  yourself: `puff check local` checks everything under `local`. When you
  search a directory outside the project root (for example
  `puff check /other/proj`, or `--config ci/puff.toml .`), anchored entries
  are anchored to that directory instead.
- An entry without a `/` matches any path segment with that name, at any
  depth (`vendor` skips `vendor/` and `lib/vendor/`).
- Any other entry matches a path prefix relative to the directory being
  searched (`t/corpus` skips `t/corpus/x.pl` but not `xt/corpus/x.pl`).

A file named on the command line is never excluded.

Command-line flags override the file. `--select` replaces `select`.
`--extend-select` and `--ignore` are added to the configured lists.
`--unsafe-fixes` overrides `unsafe-fixes`.

### `rule-paths` runs code

**Warning:** when `rule-paths` is set, puff loads and executes every `.pm`
file under those directories, with your privileges. Running puff in a
repository whose `.puff.toml` sets `rule-paths` is as risky as running that
repository's tests. Do not run puff on code you do not trust without
`--no-config`, which ignores the config file and so does not load any rules
from it.

## Suppressions

Silence a rule on one line with a comment on that line:

    my $r = rand(10);    # puff: ignore S001

Silence a rule for the whole file with a comment anywhere in it:

    # puff: ignore-file S002

List several codes separated by spaces or commas. Codes are prefixes, so
`# puff: ignore S` silences every `S` rule. A code is capital letters
optionally followed by digits; other words in the comment (`# puff: ignore
S002 legacy code`) are ignored. `ignore` must be followed by a space or the
end of the comment: `# puff: ignore-foo S002` is not a suppression. Only real comments count, not
text inside a string. A suppressed violation is neither reported nor fixed.

A suppression comment that lists no codes suppresses nothing and is itself
reported as `P001`:

    $ puff check p.pl
    p.pl:1:1: P001 suppression comment must list codes
    Found 1 violation (checked 1 file).

## Rules

| Code | Name | Summary | Fix safety | CWE |
| --- | --- | --- | --- | --- |
| S001 | InsecureRand | `rand`/`srand` is not cryptographically secure | unsafe | [338](https://cwe.mitre.org/data/definitions/338.html) |
| S002 | TwoArgOpen | Use three-argument open | unsafe | [78](https://cwe.mitre.org/data/definitions/78.html), [73](https://cwe.mitre.org/data/definitions/73.html) |
| S003 | BarewordFilehandle | Use a lexical filehandle instead of a bareword | unsafe | [1108](https://cwe.mitre.org/data/definitions/1108.html) |
| S004 | StringEval | Do not `eval` a string built at runtime | none | [95](https://cwe.mitre.org/data/definitions/95.html) |
| S005 | TLSVerifyDisabled | Do not turn off TLS certificate or SSH host key verification | unsafe | [295](https://cwe.mitre.org/data/definitions/295.html) |
| S006 | WeakHash | Do not use MD5, SHA-1 or `crypt` for security | none | [327](https://cwe.mitre.org/data/definitions/327.html), [328](https://cwe.mitre.org/data/definitions/328.html), [916](https://cwe.mitre.org/data/definitions/916.html) |
| S007 | InsecureTempFile | Do not build a temporary file name yourself | none | [377](https://cwe.mitre.org/data/definitions/377.html) |
| S008 | ShellCommand | Do not pass a command built at runtime to the shell | none | [78](https://cwe.mitre.org/data/definitions/78.html) |
| S009 | WorldWritable | Do not make files world-writable | none | [732](https://cwe.mitre.org/data/definitions/732.html) |
| S010 | PredictableToken | Do not hash the time, PID or `rand` to make a token | none | [340](https://cwe.mitre.org/data/definitions/340.html), [338](https://cwe.mitre.org/data/definitions/338.html) |
| S011 | TimingCompare | Compare secrets in constant time | none | [208](https://cwe.mitre.org/data/definitions/208.html) |
| S012 | UnsafeDeserialize | Do not deserialize untrusted data with Storable or code-loading YAML | unsafe | [502](https://cwe.mitre.org/data/definitions/502.html) |
| S013 | SQLInjection | Variable interpolated or concatenated into SQL | none | [89](https://cwe.mitre.org/data/definitions/89.html) |
| S014 | ExtensionRegex | Anchor a file extension check with `\z` | unsafe | [184](https://cwe.mitre.org/data/definitions/184.html) |
| S015 | PathPrefix | Directory containment checked with a bare prefix test | unsafe | [22](https://cwe.mitre.org/data/definitions/22.html) |
| S016 | RequireRuntimePath | Do not require or do a file name computed at runtime | none | [829](https://cwe.mitre.org/data/definitions/829.html) |
| S017 | HTMLEscapeQuote | Escape ' in a hand-written HTML escaper | unsafe | [79](https://cwe.mitre.org/data/definitions/79.html) |
| Q001 | SimpleStringQuotes | Use single quotes for a string with nothing to interpolate | safe |  |
| Q002 | HashKeyQuotes | Hash key does not need quotes | safe |  |
| Q003 | EmptyQuotes | Use q{} for an empty string | safe |  |
| B001 | UselessRegexModifiers | Modifiers on a match against a lone qr// object are ignored | unsafe |  |
| B002 | AggregateAssignRef | Array or hash assigned a `[...]` or `{...}` reference | unsafe |  |
| B003 | LeadingZeros | Number with a leading zero is octal | safe |  |
| B004 | IndirectObject | Indirect object syntax | unsafe |  |
| B005 | TryTinySemicolon | Try::Tiny try/catch is not ended with a semicolon | unsafe |  |
| B006 | UnusedVariable | Lexical variable is declared but never used | unsafe |  |
| M001 | RequireMakeImmutable | Moose class never calls make_immutable | unsafe |  |
| U001 | UseParent | use base instead of use parent | unsafe |  |
| A001 | DollarAB | Do not use `$a` or `$b` outside sort and pair functions | none |  |
| P001 | (built in) | Suppression comment must list codes | none |  |

Rule codes follow ruff's prefixes where ruff has an equivalent, so a ruff
user can guess where a rule lives:

| Prefix | Meaning | Ruff equivalent |
| --- | --- | --- |
| `S` | Security; selected by default | `S` (flake8-bandit) |
| `Q` | Quotes | `Q` (flake8-quotes) |
| `B` | Likely bugs; selected by default | `B` (flake8-bugbear) |
| `M` | Moose and Mouse classes | none |
| `U` | Upgrades to newer idioms | `UP` (pyupgrade) |
| `A` | Misused builtin variables | `A` (flake8-builtins) |
| `P` | puff's own checks; always on | none |

`puff rule CODE` prints the full explanation of a rule. When a fix is
declined, the violation is still reported, without a marker.

**S001** reports `rand`, `srand`, `CORE::rand` and `CORE::srand`. The fix
adds `use Crypt::PRNG qw(rand);` once per file; Crypt::PRNG's `rand` is a
drop-in for the built-in. It does not fix:

- `srand`, `CORE::rand` and `CORE::srand` (an import cannot override `CORE::`
  names);
- a file with more than one `package` statement, a block-form
  `package NAME { ... }`, or a `package` after the first `rand` call.

Plain `rand` is not reported at all when the file already imports `rand` from
Crypt::PRNG (by name or with `:all`) or from Math::Random::Secure. Where the
random value becomes a key, token or salt, use `random_bytes` from Crypt::PRNG
or Crypt::SysRandom instead; puff leaves that rewrite to you.

**S002** reports two-argument `open`, except the forking `open($fh, '-|')`
and `open($fh, '|-')`. The fix rewrites `open(FH, "<$file")` as
`open(FH, '<', $file)`. It does not fix a second argument that:

- is anything but a single `'...'` or `"..."` string or a single scalar
  variable;
- is empty, starts with `|` or `&`, ends with `|`, or is `-`;
- has a mode but no filename, or a filename that starts with `&` or is `-`;
- is a `"..."` string that starts with a variable (the mode could be inside
  it);
- has an escape such as `\t`, `\n`, `\x20`, `\040` or `\x{20}` at the start
  or end of the mode or filename, since two-argument open strips that
  whitespace at runtime.

**S003** reports `open`, `opendir`, `sysopen` and `socket` with a bareword
first argument other than `STDIN`, `STDOUT`, `STDERR`, `DATA`, `ARGV`,
`ARGVOUT` or `_`. The fix rewrites the handle as `my $name` and renames its
uses in the same block. It does not fix:

- `socket`;
- an open that is not at the start of its own statement, is part of a
  condition, or has a statement modifier;
- a handle used in the open's own statement (`open(...) and print FH`);
- a name opened more than once in the file, or opened alongside another
  handle whose name differs only in case (`LOG` and `Log`);
- `print FH`, `printf FH` or `say FH` with nothing to print after the handle
  (`print FH;`, `print FH if $x;`, `{ print FH }`);
- a name used before the open, outside the open's block, in a different named
  sub, or after a `package` statement;
- any other use of the name: passed to a sub, `select`, file tests, `write`,
  `*FH` globs, a package-qualified name, or the name appearing inside any
  string (it could be a string eval or a symbolic reference).

**S004** reports `eval` (and `CORE::eval`) with a string argument, or with
no argument (which evals `$_`). A single constant string with nothing
interpolated, such as `eval 'use Foo; 1'`, is allowed. Block `eval { ... }` is
never reported. There is no fix.

**S005** reports turning TLS certificate or SSH host key verification off:

- `verify_hostname => 0`, `verify_SSL => 0` and `SSL_verify_mode => 0` (or
  `SSL_VERIFY_NONE`), with `0`, `''` or `'0'` as the value;
- `insecure => 1` and `->insecure(1)` (Mojo::UserAgent);
- assigning a false value to `$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME}`;
- `strict_hostkeycheck => 0`, `strict_host_key_checking => 'no'`, and a
  string holding `StrictHostKeyChecking=no`.

A value that is a variable is not reported. The unsafe fix turns TLS
verification back on (`0` becomes `1`, `SSL_VERIFY_NONE` becomes
`SSL_VERIFY_PEER`, `insecure` gets `0`); SSH settings are not fixed.

**S006** reports:

- `use` or `require` of Digest::MD5, Digest::MD4, Digest::MD2, Digest::SHA1
  or Digest::Perl::MD5;
- importing a `sha1*` function from Digest::SHA, or calling one by its full
  name;
- `Digest->new('MD5')`, `Digest->new('SHA-1')` and similar;
- `Digest::SHA->new` with no algorithm (it defaults to SHA-1) or with `1`;
- `crypt`.

MD5 and SHA-1 are fine as checksums or cache keys, or where a protocol
requires them; suppress the violation there with `# puff: ignore S006`.
There is no fix.

**S007** reports a string literal naming a file in `/tmp`, `/var/tmp` or
`/dev/shm` (`"/tmp/report.$$"`, or `'/tmp/' . $name`), and calls to
`mktemp`, `tempnam` and `POSIX::tmpnam`. File::Temp's `tmpnam` is reported
only in scalar context (`my $name = tmpnam()`, `scalar(tmpnam())`,
`tmpnam() . $suffix`), where it returns a name without creating the file; in
list context it creates the file safely. A directory on its own
(`DIR => '/tmp'`) is not reported. Use File::Temp's `tempfile` or `File::Temp->new` instead. Change
the directories with:

    [rules.S007]
    tmp-directories = ["/tmp", "/var/tmp", "/dev/shm", "/scratch"]

There is no fix.

**S008** reports a command that reaches the shell as one string built at
runtime: `system`, `exec` or `readpipe` with a single argument that is not a
constant string (`system("tar xf $file")`, `system($cmd)`), backticks and
`qx{...}` that interpolate, and three-argument `open` with mode `-|` or `|-`
and one non-constant command string. The list forms (`system('tar', 'xf',
$file)`, `system(@cmd)`, `open($fh, '-|', 'git', 'log', $ref)`) are not
reported. There is no fix.

**S009** reports `chmod` with a constant world-writable mode (`chmod 0777,
$dir`, `chmod 0666, $file`), the same through a `->chmod` method (including
symbolic modes such as `'o+w'`), and `umask` with a constant mask that does
not mask other-write (`umask 0`). Sticky-bit modes such as `01777` are
allowed. Modes passed to `mkdir`, `sysopen` and `make_path` are not reported,
since the umask filters them. There is no fix.

**S010** reports md2, md4, md5 and sha* digest functions (`md5_hex`,
`sha256_hex`, `sha256_b64u` and the rest) and Crypt::Digest's `digest_data*`
whose arguments use `time`, `localtime`, `gmtime`, `times`, `gettimeofday`,
`clock_gettime`, `rand`, `srand`, `refaddr`, `$$` or English's `$PID`, as in
`md5_hex( time . $$ . rand )`. That is how several CPAN session modules made
guessable session IDs. Use `random_bytes` from Crypt::PRNG or
Crypt::SysRandom for tokens; suppress the violation for cache keys. There is
no fix. It covers Perl::Critic::Policy::Security::RandBytesFromHash, except
that a `join` on its own is not reported.

**S011** reports `eq` and `ne` where one side looks like a secret and the
other is not a constant, so the comparison time leaks how much of a guess was
right. Names ending in password, passwd, secret, csrf, nonce or hmac (or
starting with hmac_) always count. Names ending in token, sig, signature,
digest, mac or hash count only in files that use hmac functions or a
Crypt/Authen/OAuth/JWT/Session/HMAC module or package, since elsewhere they
are usually parser tokens, sigils and data structures. It is a name
heuristic; suppress it where the value is not secret. Use a constant-time
comparison such as String::Compare::ConstantTime's `equals`. There is no fix.

**S012** reports Storable's `thaw`, `retrieve`, `lock_retrieve` and
`fd_retrieve` (fully qualified, or called as functions in a file that loads
Storable), and setting `$Storable::Eval` or the LoadBlessed, LoadCode,
UseCode or EvalCode variables of YAML, YAML::XS or YAML::Syck to a true
constant, and YAML or YAML::XS `Load` and `LoadFile`, which bless objects by
default, unless the file sets that module's `$LoadBlessed` to a false
constant (a `local` counts in its own block). Use JSON for data that crosses
a trust boundary, and suppress the violation where the program reads back
only what it wrote. The unsafe fix wraps a YAML `Load(...)` call as
`do { local $YAML::XS::LoadBlessed = 0; Load(...) }`; Storable is not fixed.

**S013** reports a variable or function call that is interpolated, concatenated
or passed through `sprintf %s` into a string that starts like an SQL
statement (`SELECT ... FROM`, `INSERT INTO`, `UPDATE ... SET`, `DELETE FROM`,
`CREATE TABLE` and the like), into a `<<SQL` heredoc, or appended with `.=`
to such a string. Values passed through `$dbh->quote` or `quote_identifier`,
constants, and numeric functions such as `int` are allowed, and a
`## SQL safe ($var)` comment marks a variable as checked. Use placeholders.
The options `quoting-methods`, `safe-functions` and `upper-case-keywords`
tune it. There is no fix.

**S014** reports a match or `qr//` whose whole pattern is a file extension
(`\.(pl|cgi)`, `\.pm`, or `\Q$ext\E` where the variable name contains `ext` or
`suffix`) that has no end anchor, or ends in `$` or `\Z`, which also match
before a trailing newline. A suffix passed to `basename` or `fileparse` is
not reported. The unsafe fix anchors the pattern with `\z`.

**S015** reports a prefix test used to check that a path is inside a
directory: `index($path, $root) == 0` (or `!index`, `!= 0`),
`substr($path, 0, length $root) eq $root`, and `$path =~ /^\Q$root\E/`,
when the prefix variable's name contains root, dir, base, home, top, parent,
folder or path. Such a test lets `/srv/www-private` pass for `/srv/www`. The
unsafe fix rewrites the `index` and regex forms as
`$path =~ m{\A\Q$root\E(?:/|\z|(?<=/))}`; the substr form is not fixed.

**S016** reports `require` and `do` of a file name built from a variable
(`require $file`, `require "$class.pm"`, `do "$repo/.env.pl"`), which runs
whatever file the value names. It is not reported when the same sub checks a
name against an anchored module-name pattern such as `/\A\w+(?:::\w+)*\z/`.
Check the name against an allowlist and load it with Module::Runtime's
`require_module`. There is no fix.

**S017** reports a hand-written HTML escaper whose substitutions, in one sub
or at the top level of a file, escape `<` and `"` but never match `'`. Its
output is not safe inside a single-quoted attribute. The unsafe fix adds
`s/'/&#39;/g` after the `"` substitution, with the same target, delimiters
and modifiers; an escaper that uses a character class and a lookup table
(`s/([&<>"])/$ESCAPE{$1}/g`) is reported but not fixed.

**Q001** is not selected by default; turn it on with `--select Q` or
`extend-select = ["Q"]`. It reports a `"..."` string whose text has no
backslash, `$`, `@`, `'` or `"`, and the safe fix rewrites `"coffee"` as
`'coffee'`. `qq{...}` and heredocs are left alone.

**Q002** is not selected by default either. It reports a quoted hash key
that Perl would quote by itself: the only key in a `{...}` subscript
(`$h{'name'}`) or the string just left of `=>` (`'name' => 1`), when its
text is a plain ASCII identifier. The safe fix removes the quotes. Numbers,
names with `::` or `-`, v-strings, quote-like operator names such as `s` and
`y`, and multi-key slices keep their quotes.

**Q003** is not selected by default either. It reports `''` and `""`, which
are easy to misread, and the safe fix rewrites them as `q{}`. An empty hash
key such as `$h{''}` is left alone, since `$h{q{}}` is harder to read.

**B001** is selected by default. It reports pattern modifiers such as `/i`,
`/m`, `/s` and `/x` on a match, substitution or `split` whose whole pattern
is one variable that the file only assigns a `qr//` to. Perl ignores them
(since 5.10, silently), so `$str =~ /$re/i` is still case-sensitive. Put the
modifiers in the `qr//`. The unsafe fix deletes the ignored modifiers, which
keeps the current behaviour. It is unsafe because the rule sees only this
file's assignments. Based on
Perl::Critic::Policy::Bangs::ProhibitUselessRegexModifiers, which checks only
`/m` and `/s`.

**B002** is selected by default. It reports assigning a `[...]` or `{...}`
constructor to an array, hash, dereferenced array or hash, or slice:
`my @names = [ 'ann', 'bob' ]` stores one arrayref, not two names. Write
`( ... )` for a list, or `( [ ... ] )` when one reference is what you mean. The
unsafe fix turns the brackets or braces into parens, and is offered only when
the constructor is the whole right side. Based on
Perl::Critic::Policy::ValuesAndExpressions::ProhibitArrayAssignAref from
Perl::Critic::Pulp, extended to hashes.

**B003** is selected by default. It reports a number literal with a leading
zero, which Perl reads as octal: `my $count = 010` is 8. The mode argument of
`chmod`, `umask`, `mkdir`, `mkfifo`, `dbmopen`, `sysopen` and `mkpath`, a value
after a `mode` or `perm` key, and an operand of a bitwise operator
(`$mode & 07777`) are octal by convention and not reported unless the `strict`
option is on. The safe fix rewrites the literal as `oct('0755')`, which
compiles to the same constant. Based on
Perl::Critic::Policy::ValuesAndExpressions::ProhibitLeadingZeros.

**B004** is selected by default. It reports indirect object syntax such as
`new Foo(...)` or `bootstrap Foo $VERSION`, where Perl has to guess that a
method call was meant. A lowercase non-builtin word followed by a class name
(or, for `new`, a `$variable`) is reported. The unsafe fix rewrites it as
`Foo->new(...)`; it is unsafe because an imported function with that name
would be called today. Based on Perl::Critic::Policy::Dynamic::NoIndirect,
which compiles the code under indirect.pm; this rule reads the source.

**B005** is selected by default. In a file that loads Try::Tiny or Try::Catch,
it reports a `try`/`catch`/`finally` whose last block is followed by more
code instead of `;`. That code becomes arguments to `try` and runs before it,
or not at all if it returns. The unsafe fix adds the semicolon. The `modules`
option adds your own Try::Tiny wrappers; the `try` feature and
Syntax::Keyword::Try need no semicolon and are not affected. Based on
Perl::Critic::Policy::TryTiny::RequireBlockTermination.

**B006** is selected by default. It reports a `my` or `state` variable that
is never mentioned after its declaration in the same scope, counting
interpolation into strings, regexes and heredocs. Subroutine arguments
(`my ( $self, $c ) = @_;`) are allowed unless you turn off
`allow-unused-subroutine-arguments`, and `allow-if-computed-by` lists guard
functions and classes whose result is kept only to be destroyed later. The
unsafe fix replaces an unused list member with `undef` when the values come
from a builtin such as `split` or `caller`, `@_` or a regex match, and
deletes a declaration that has no assignment. Based on
Perl::Critic::Policy::Variables::ProhibitUnusedVarsStricter, limited to
statement-level declarations.

**M001** is not selected by default; turn it on with `--select M`. It reports
`use Moose` or `use Mouse` in a package that never calls `->make_immutable`,
so every `new` builds the constructor at runtime. Each package is checked on
its own. `use Moose ()` and roles are not reported, and the `modules` option
adds your own Moose::Exporter modules. The unsafe fix inserts
`__PACKAGE__->meta->make_immutable;` before the `1;` that ends the package;
it is unsafe because code that changes the class at runtime dies once the
class is immutable. Based on Perl::Critic::Policy::Moose::RequireMakeImmutable,
which checks the whole file at once.

**U001** is not selected by default; turn it on with `--select U`. It reports
`use base`, which carries on when a parent class fails to load. The unsafe fix
rewrites it as `use parent`, adding `-norequire` when every parent is declared
in the same file (or is a Tie::StdHash-style class whose module the file
loads). It is unsafe because `use parent` dies where `use base` quietly went
on. Based on Perl::Critic::Policy::Tics::ProhibitUseBase.

**A001** is not selected by default; turn it on with `--select A`. It reports
`$a` and `$b` outside a block passed directly to `sort`, `reduce`,
`reductions`, `pairgrep`, `pairfirst`, `pairmap` or `pairwise`, and outside a
named sub the file uses as `sort NAME`. A sub stored in a variable
(`my $cmp = sub { $a <=> $b }`) is reported; suppress it there. `$a[0]`, `@a`
and `$main::a` are different variables and are not reported. There is no fix.
To allow more functions that set `$a` and `$b`:

    [rules.A001]
    extra-pair-functions = ["pairfoo"]

## Writing a rule

A rule is a subclass of `Puff::Rule`. The full API is documented in
`perldoc Puff::Rule`. This is a complete rule that rewrites `FIXME` comments
as `TODO` (it is `t/lib-rules/NoFixme.pm`, and `t/readme-rule.t` runs it, so
the example works):

    package Local::Rule::NoFixme;

    use v5.36;
    use parent 'Puff::Rule';

    sub code       {'X001'}
    sub summary    {'Use TODO instead of FIXME'}
    sub applies_to {'PPI::Token::Comment'}
    sub fix_safety {'safe'}
    sub options    { { keyword => 'FIXME' } }

    sub explanation {
        return <<~'END';
            This project marks open work with TODO. A FIXME comment is reported
            and the fix rewrites it as TODO. The word to look for can be changed
            with the `keyword` option.
            END
    }

    sub check ( $self, $elem, $doc ) {
        my $keyword = $self->option('keyword');
        return unless $elem->content =~ /\b\Q$keyword\E\b/;
        return $self->violation( $elem, message => "Use TODO instead of $keyword" );
    }

    sub fix ( $self, $violation, $fix ) {
        my $elem    = $violation->element;
        my $keyword = $self->option('keyword');
        return 0 unless $elem->content =~ /\b\Q$keyword\E\b/;

        my $start = $fix->source->start_of($elem) + $-[0];
        $fix->replace_range( $start, $start + length $keyword, 'TODO' );
        return 1;
    }

    1;

Put the module in a directory and point `rule-paths` at it (a relative path
is relative to the config file; an absolute path also works). This also
enables the `X` rules, because only `S` and `B` are enabled by default:

    # .puff.toml
    rule-paths    = ["xt/puff-rules"]
    extend-select = ["X"]

    [rules.X001]
    keyword = "FIXME"

puff loads every `.pm` file under `rule-paths` and treats each package that
inherits from `Puff::Rule` as a rule. A code must be letters followed by
three digits and must be unique. `P001` is reserved, and so is any code
starting with `ALL`, because `ALL` selects every rule. Then:

    $ puff rules
    S001   unsafe  rand/srand is not cryptographically secure
    S002   unsafe  Use three-argument open
    S003   unsafe  Use a lexical filehandle instead of a bareword
    X001   safe    Use TODO instead of FIXME
    P001   none    suppression comment must list codes

Given this `lib/a.pl`:

    # FIXME: tidy up
    print 1;      # FIXME later

`puff check` reports both comments:

    $ puff check
    lib/a.pl:1:1: X001 Use TODO instead of FIXME [*]
    lib/a.pl:2:15: X001 Use TODO instead of FIXME [*]
    Found 2 violations (checked 1 file).
    2 fixable with --fix

The points to know:

- `applies_to` limits which elements `check` sees. Name the narrowest PPI
  class you can.
- `check` returns violations built with `$self->violation`. The message
  defaults to the rule's `summary`. Pass `fixable => 0` for a violation
  that has no fix, so the report does not offer one.
- `fix` records edits on the `$fix` object and returns true, or returns false
  (or calls `Puff::Fix->decline($why)`) to decline. If `fix` dies any other
  way, that is a bug in the rule: puff reports an error for the file
  (exit `2`) and writes none of its fixes. The edits are text offsets into
  the file, so you can change part of an element with `replace_range`.
- Use `fix_safety => 'unsafe'` for any fix that can change behaviour.
- If the rule detects a known weakness, return its CWE numbers from `cwe`
  (`sub cwe { ( 78, 73 ) }`); `puff rule CODE` prints them.
- Rules that ship with puff go under `lib/Puff/Rule/` and are found
  automatically.

### Testing a rule: the corpus

Each rule is tested with fixture files in a corpus directory, by default
`t/corpus/CODE/`:

- `NAME.pl` is a fixture. Put `# expect: CODE` on every line where the rule
  must report a violation. Repeat the code (`# expect: S001 S001`) for a line
  with two violations. Lines with no comment must report nothing.
- `NAME.fixed.pl` is the text the fixer must produce from `NAME.pl` with
  unsafe fixes on. If there is no `NAME.fixed.pl`, the fixer must leave the
  file unchanged. This is how declined cases are covered.

`Puff::Test` (it ships with puff, see `perldoc Puff::Test`) provides
`run_corpus($code, %args)`, which finds the rule with that code and runs one
subtest per fixture. For each file it checks that the reported lines match
the `# expect:` comments, that fixing gives the `.fixed.pl` text (or no
change), and that no fixable violation of that rule is left after fixing.

A rule of your own lives outside `Puff::Rule::`, so tell `run_corpus` where
to load it from with `rule_paths` (as in the config file, but relative to
the directory the tests run from). For the X001 rule above, with fixtures
in `t/corpus/X001/`, the whole test file is:

    use v5.36;
    use Test2::V0;
    use Puff::Test qw( run_corpus );

    run_corpus( 'X001', rule_paths => ['xt/puff-rules'] );

    done_testing;

Pass `dir => 'path/to/corpus'` to use a different corpus directory. The
built-in rules need neither argument: `t/rule-S001.t` is just
`run_corpus('S001')`. Run the tests from the repository root:

    prove -lr -Ilocal/lib/perl5 t
