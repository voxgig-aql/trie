# Verifying the trie library against `aql` main — interpret / check / compile

**Date:** 2026-06-23
**aql tested:** `main` @ `f8ee64269fa10f6a0c1b2d9b953ad904a9e7e51d`, retested @
`65410b18565ea64ba4fc2a55a73eeb04fa90401f` (both built from source)
**aql currently pinned:** `c44d994f33c5cc39b2a1cc4d2f170b3b0aa07431`
**Library:** `voxgig-aql/trie` (standard trie + radix / tst / burst variants)

> **Retest note (`65410b18`, 5 commits past `f8ee6426`, incl. a
> "bytecode-compiler-impl" merge):** the verdict is **unchanged** — only
> interpreting works fully. The library's own `check` error count dropped
> (`trie.aql` 190 → 150), but the transitive-import check still gates check
> and compile. See [§5 Retest](#5-retest-at-65410b18) at the end.

## Task

Download the latest `aql` from `main`, then confirm that **interpreting**,
**checking** (`aql check`), and **compiling** (`aql --force-compile`, the
bytecode VM) all work fully against this library.

## Verdict

| Mode | Command | Result |
|---|---|---|
| **Interpreting** | `aql <suite>.aql` | ✅ **Works fully** — all 11 suites green |
| **Checking** | `aql check <suite>.aql` | ❌ **Broken** — error-level diagnostics on every suite |
| **Compiling** | `aql --force-compile <suite>.aql` | ❌ **Blocked** — aborts on `check diagnostics` before the emitter runs |

Only interpreting works fully on `main`. Checking and compiling regressed in
the `c44d994f → f8ee6426` window — **not** because of anything in this
library, but because `aql check` changed shape (see below). On the pinned
`c44d994f`, all three modes work fully.

---

## Detail

### 1. Interpreting — ✅ fully green

All eleven suites pass on `main`:

```
PASS test/burst_prop_spec.aql     PASS test/trie_prop_test.aql
PASS test/burst_unit_test.aql     PASS test/trie_smoke_test.aql
PASS test/radix_prop_spec.aql     PASS test/trie_unit_spec.aql
PASS test/radix_unit_test.aql     PASS test/trie_unit_test.aql
PASS test/trie_prop_spec.aql      PASS test/tst_prop_spec.aql
                                  PASS test/tst_unit_test.aql
```

The interpreter is the default, supported execution path; nothing here
regressed.

### 2. The emitter genuinely improved — `fold` / `each` now compile

A real step forward in this window. On the pinned `c44d994f`, a bare
`fold` / `each` body refused to lower:

```
$ aql --force-compile fold.aql      # c44d994f
error: force-compile: fn fold$body: result above a literal (Stage 3)
```

On `main`, the same programs compile and run on the VM:

```
$ aql --force-compile fold.aql      # main: 0 [1 2 3] [var[[x acc] acc x add]] fold
6
$ aql --force-compile each.aql      # main: [1 2 3] each [var[[x] x 1 add]]
[2, 3, 4]
```

This is the exact Stage-3 gap that kept the property and spec suites
interpreter-only. The compiler has closed it — so those suites *would* now be
compilable, were it not for the regression in §3.

### 3. `aql check` became transitive — and that breaks check **and** compile

`main`'s `aql check` "drives the same engine in carrier mode — so checking
stays in lockstep with runtime dispatch" (CLI.md). Concretely, **check now
follows `import`s and analyses the imported module**, so a consumer inherits
the library's diagnostics.

A two-line script that only imports the library demonstrates the change:

```aql
import "./trie.aql"
((TrieSet.make) "x" TrieSet.add) "x" TrieSet.has print end
```

| aql | `aql check` on that script |
|---|---|
| `c44d994f` (pinned) | `0 error(s), 0 warning(s)` |
| `f8ee6426` (main)   | `28 error(s)` |

The library modules' own counts rose too: `aql check trie.aql` went from
**106 → 190** errors.

The four imperative unit suites — engineered to be **0-error** on `c44d994f`
and gated three-ways in CI — now report errors sourced entirely from the
imported library:

| suite | error-level diagnostics on `main` |
|---|---|
| `trie_unit_test`  | 16 `no_signature`, 1 `undefined_word` |
| `radix_unit_test` | 50 `no_signature`, 8 `undefined_word` |
| `tst_unit_test`   | 70 `no_signature` |
| `burst_unit_test` | 28 `no_signature` |

Every one is a **documented false positive** (see `AQL-CHECK-REPORT.md`):

- `no_signature` on `Any`-typed dynamic dispatch — the diagnostics point at
  library internals (`get`, `find-kid`, `trie-insert`, `mk-node`,
  `put-kid`), i.e. the generic "pull an untyped child node, walk it" shape
  the whole library is built on.
- `undefined_word` on `do {…}` quotation params (`kids`).

None corresponds to a real defect: all suites run green on the interpreter.

### 4. Why compiling is blocked (no workaround)

`--force-compile` does not have an independent emitter gate it can reach here.
The compiled stream **is** the check pass, and it refuses on any error-level
diagnostic before emitting:

```go
// lang/go/aql.go
for _, d := range res.Diagnostics {
    if d.Severity == SeverityError {
        return nil, "check diagnostics", res, nil
    }
}
```

So on `main`, every suite fails with:

```
error: force-compile: check diagnostics
```

There is no bypass: `--soft` applies to `aql check`, not to `run` /
`--force-compile`; there is no "don't follow imports" flag. The emitter's new
`fold`/`each` support (§2) cannot be reached because the transitive check
errors (§3) gate it out first.

---

## Root cause and blast radius

The transitive `aql check` is the single cause of both failures. It is an
**upstream change**, not a library regression — this library's own test files
remain clean of their *own* diagnostics; the errors are inherited from the
imported module.

What used to be advisory CI noise (the library's ~hundreds of documented
`check` false positives, run with `--soft` + `continue-on-error`) is now
**load-bearing**: because check follows imports *and* gates compilation, the
library is currently **uncheckable and uncompilable for any downstream
consumer** on `main`. That is a far larger blast radius than before.

This sharpens — does not change — the standing wishlist from
`AQL-CHECK-REPORT.md` (items 1–4): until `aql check` can distinguish this
library's deliberate dynamic dispatch from a real error
(trace `/r` reference-exports, unify `Any` with concrete params, resolve
`do{}` quotation params, declare `Returns` on core words), the transitive
check blocks check and compile for the whole ecosystem downstream of it.

---

## Recommendation

- **Do not re-pin** from `c44d994f` to `f8ee6426`. On `main`, the CI `check`
  (0 errors) and `--force-compile` gates for the unit suites would both turn
  red — caused by the imported library's transitive false positives, not by
  test code. `c44d994f` is the newest commit where all three modes work
  fully; keep the pin there.
- **Upstream:** the emitter progress (`fold`/`each` lowering) is worth
  adopting — but only once the transitive-check change either (a) does not
  surface imported-module diagnostics as gating errors for a consumer, or
  (b) the library's documented false-positive classes are resolved
  (wishlist items 1–4). Either unblocks check + compile across the board.

## Reproduction

```bash
# Build main
git clone https://github.com/aql-lang/aql /tmp/aql-src
git -C /tmp/aql-src checkout f8ee64269fa10f6a0c1b2d9b953ad904a9e7e51d
( cd /tmp/aql-src/cmd/go && GOFLAGS=-mod=mod go build -o /tmp/aql-main ./aql )

# 1. interpret — green
for f in test/*.aql; do /tmp/aql-main "$f" >/dev/null && echo "PASS $f"; done

# 2. check — errors (transitive, from the imported library)
for f in trie radix tst burst; do /tmp/aql-main check "test/${f}_unit_test.aql"; done

# 3. compile — blocked on the check gate
for f in trie radix tst burst; do /tmp/aql-main --force-compile "test/${f}_unit_test.aql"; done

# the change in one probe:
printf 'import "./trie.aql"\n((TrieSet.make) "x" TrieSet.add) "x" TrieSet.has print end\n' > /tmp/imp.aql
aql            check /tmp/imp.aql   # c44d994f → 0 errors
/tmp/aql-main  check /tmp/imp.aql   # f8ee6426 → 28 errors
```

---

## 5. Retest at `65410b18`

Re-ran the full pass against `main` @
`65410b18565ea64ba4fc2a55a73eeb04fa90401f` — 5 commits past `f8ee6426`,
including the #180 "bytecode-compiler-impl" merge. **The verdict is
unchanged:** interpreting works fully; checking and compiling are still
blocked by the transitive-import check.

| Mode | `f8ee6426` | `65410b18` |
|---|---|---|
| Interpreting (11 suites) | ✅ green | ✅ green |
| `aql check` import-only probe | 28 errors | **28 errors** (unchanged) |
| `aql check` unit suites (trie/radix/tst/burst) | 17 / 58 / 70 / 28 | **17 / 58 / 70 / 28** (unchanged) |
| `--force-compile` unit suites | ❌ `check diagnostics` | ❌ `check diagnostics` |
| `aql check trie.aql` (module direct) | 190 errors | **150 errors** |
| bare `fold` / `each` `--force-compile` | ✅ `6` / `[2,3,4]` | ✅ `6` / `[2,3,4]` |

**What moved:** the library's *own* `check` error count fell from 190 to
150 on `trie.aql`, so this window trimmed some of the false-positive classes
— real progress, but far short of the zero needed to clear the gate.

**What did not move:** the transitive-import check is identical (an
import-only script still inherits 28 errors from the library), so it still
gates both `aql check` and `--force-compile` on every suite. The emitter is
still healthy (`fold`/`each` lower and run), and still unreachable behind the
check gate for any program that imports the library.

**Conclusion holds:** keep the pin at `c44d994f`. Adopting `main` still waits
on the transitive-check change no longer surfacing imported-module
diagnostics as gating errors, or on the library's documented false-positive
classes being resolved upstream (`AQL-CHECK-REPORT.md` wishlist 1–4).

### Access note

The session's git credential relay began returning **403 for
`aql-lang/aql`** (`git fetch`/`clone` of that repo), though it worked earlier
in the session. GitHub egress itself is allowed (a direct HTTPS request
returns 200), so this run fetched `main` via the public source tarball
(`https://codeload.github.com/aql-lang/aql/tar.gz/<sha>`) and built from
that. Re-pinning still only needs the commit SHA, which the GitHub API
(`/repos/aql-lang/aql/commits/main`) returns.
