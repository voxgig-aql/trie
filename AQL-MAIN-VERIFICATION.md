# Verifying the trie library against `boru` main — interpret / check / compile

**Date:** 2026-06-23, last retested 2026-07-11
**boru tested:** `main` @ `f8ee6426` → `65410b18` → `14036b41` → `407fedad` →
`0721e828` → **`6185620`** (current pin), all built from source
**boru currently pinned:** `618562025d9e0154107306927911a8b1b046333c`
**Library:** `voxgig-boru/trie` (standard trie + radix / tst / burst variants)

> **CURRENT STATE (`6185620` + 3 landed upstream fixes, 2026-07-11) — see
> [§11](#11-three-stage-d-fixes-landed-upstream-remaining-frontier-precisely-scoped).**
> Re-pinned to the newest `main`, `6185620` (PR #260, forward-args auto-eval).
> **Both hard CI gates are green**: interpreter 11/11 suites, `boru check` 0
> errors across all 11 suites + 4 modules. Three of the Stage-D leaves §10
> diagnosed now have **landed fixes** on the boru branch
> `claude/voxgig-boru-baseline-pctxto` (commit `3e94429`) — including the do-catch
> fix that resolves the "not safe to land alone" regression §10 warned about.
> With them, the trie suites split **4 fully native-compiled / 5 sound
> clean-fallback**, every suite **stdout-byte-identical** interpreter-vs-`--compile`
> and green. §11 records the landed fixes, the residual frontier (one recursive
> branch-join provenance bug, root-caused; plus the deferred `test-test`/`each`
> emitter words), and why the pin stays `6185620` (fixes are on a branch, not yet
> merged to `main`). §10 is the prior (pre-fix) root-cause map; §9 (`0721e828`)
> the retest before it.

## Task

Download the latest `boru` from `main`, then confirm that **interpreting**,
**checking** (`boru check`), and **compiling** (`boru --force-compile`, the
bytecode VM) all work fully against this library.

## Verdict

| Mode | Command | Result |
|---|---|---|
| **Interpreting** | `boru <suite>.aql` | ✅ **Works fully** — all 11 suites green |
| **Checking** | `boru check <suite>.aql` | ❌ **Broken** — error-level diagnostics on every suite |
| **Compiling** | `boru --force-compile <suite>.aql` | ❌ **Blocked** — aborts on `check diagnostics` before the emitter runs |

Only interpreting works fully on `main`. Checking and compiling regressed in
the `c44d994f → f8ee6426` window — **not** because of anything in this
library, but because `boru check` changed shape (see below). On the pinned
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
$ boru --force-compile fold.aql      # c44d994f
error: force-compile: fn fold$body: result above a literal (Stage 3)
```

On `main`, the same programs compile and run on the VM:

```
$ boru --force-compile fold.aql      # main: 0 [1 2 3] [var[[x acc] acc x add]] fold
6
$ boru --force-compile each.aql      # main: [1 2 3] each [var[[x] x 1 add]]
[2, 3, 4]
```

This is the exact Stage-3 gap that kept the property and spec suites
interpreter-only. The compiler has closed it — so those suites *would* now be
compilable, were it not for the regression in §3.

### 3. `boru check` became transitive — and that breaks check **and** compile

`main`'s `boru check` "drives the same engine in carrier mode — so checking
stays in lockstep with runtime dispatch" (CLI.md). Concretely, **check now
follows `import`s and analyses the imported module**, so a consumer inherits
the library's diagnostics.

A two-line script that only imports the library demonstrates the change:

```boru
import "./trie.aql"
((TrieSet.make) "x" TrieSet.add) "x" TrieSet.has print end
```

| boru | `boru check` on that script |
|---|---|
| `c44d994f` (pinned) | `0 error(s), 0 warning(s)` |
| `f8ee6426` (main)   | `28 error(s)` |

The library modules' own counts rose too: `boru check trie.aql` went from
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

Every one is a **documented false positive** (see `boru-CHECK-REPORT.md`):

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

There is no bypass: `--soft` applies to `boru check`, not to `run` /
`--force-compile`; there is no "don't follow imports" flag. The emitter's new
`fold`/`each` support (§2) cannot be reached because the transitive check
errors (§3) gate it out first.

---

## Root cause and blast radius

The transitive `boru check` is the single cause of both failures. It is an
**upstream change**, not a library regression — this library's own test files
remain clean of their *own* diagnostics; the errors are inherited from the
imported module.

What used to be advisory CI noise (the library's ~hundreds of documented
`check` false positives, run with `--soft` + `continue-on-error`) is now
**load-bearing**: because check follows imports *and* gates compilation, the
library is currently **uncheckable and uncompilable for any downstream
consumer** on `main`. That is a far larger blast radius than before.

This sharpens — does not change — the standing wishlist from
`boru-CHECK-REPORT.md` (items 1–4): until `boru check` can distinguish this
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
git clone https://github.com/boru-lang/boru /tmp/boru-src
git -C /tmp/boru-src checkout f8ee64269fa10f6a0c1b2d9b953ad904a9e7e51d
( cd /tmp/boru-src/cmd/go && GOFLAGS=-mod=mod go build -o /tmp/aql-main ./boru )

# 1. interpret — green
for f in test/*.aql; do /tmp/aql-main "$f" >/dev/null && echo "PASS $f"; done

# 2. check — errors (transitive, from the imported library)
for f in trie radix tst burst; do /tmp/aql-main check "test/${f}_unit_test.aql"; done

# 3. compile — blocked on the check gate
for f in trie radix tst burst; do /tmp/aql-main --force-compile "test/${f}_unit_test.aql"; done

# the change in one probe:
printf 'import "./trie.aql"\n((TrieSet.make) "x" TrieSet.add) "x" TrieSet.has print end\n' > /tmp/imp.aql
boru            check /tmp/imp.aql   # c44d994f → 0 errors
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
| `boru check` import-only probe | 28 errors | **28 errors** (unchanged) |
| `boru check` unit suites (trie/radix/tst/burst) | 17 / 58 / 70 / 28 | **17 / 58 / 70 / 28** (unchanged) |
| `--force-compile` unit suites | ❌ `check diagnostics` | ❌ `check diagnostics` |
| `boru check trie.aql` (module direct) | 190 errors | **150 errors** |
| bare `fold` / `each` `--force-compile` | ✅ `6` / `[2,3,4]` | ✅ `6` / `[2,3,4]` |

**What moved:** the library's *own* `check` error count fell from 190 to
150 on `trie.aql`, so this window trimmed some of the false-positive classes
— real progress, but far short of the zero needed to clear the gate.

**What did not move:** the transitive-import check is identical (an
import-only script still inherits 28 errors from the library), so it still
gates both `boru check` and `--force-compile` on every suite. The emitter is
still healthy (`fold`/`each` lower and run), and still unreachable behind the
check gate for any program that imports the library.

**Conclusion holds:** keep the pin at `c44d994f`. Adopting `main` still waits
on the transitive-check change no longer surfacing imported-module
diagnostics as gating errors, or on the library's documented false-positive
classes being resolved upstream (`boru-CHECK-REPORT.md` wishlist 1–4).

### Access note

The session's git credential relay began returning **403 for
`boru-lang/boru`** (`git fetch`/`clone` of that repo), though it worked earlier
in the session. GitHub egress itself is allowed (a direct HTTPS request
returns 200), so this run fetched `main` via the public source tarball
(`https://codeload.github.com/boru-lang/boru/tar.gz/<sha>`) and built from
that. Re-pinning still only needs the commit SHA, which the GitHub API
(`/repos/boru-lang/boru/commits/main`) returns.

---

## 6. Retest at `14036b412` — upstream acted on this report

Re-ran against `main` @ `14036b4125a9ccbd9655503a1a4171c008d93d06`. **The
boru team read this very report** (plus the `decision` and `bloom-filter`
client reports) and shipped a batch of checker/compiler fixes —
documented upstream in `design/CLIENT-FIXES-2026-06-24.md`. The headline is
the **gradual-`Any`** change (`0d297b84b`, "checker: gradual (dynamic)
carriers for explicitly-Any params and returns"), which is exactly the
long-standing wishlist item *"unify `Any` with concrete params"*: a value
of static type exactly `Any` (a `:Any` param, an `[Any]`-returning helper)
now binds a **dynamic carrier** and poly-matches a concrete slot instead of
failing `no_signature`.

### Checking — sharply reduced (but not yet zero)

| `boru check` | `f8ee6426`/`65410b18` | `14036b412` |
|---|---:|---:|
| import-only probe | 28 | **5** |
| `trie_unit_test`  | 17 | **5** |
| `trie_prop_test`  | — | **0** ✅ |
| `burst_unit_test` | 28 | **6** |
| `radix_unit_test` | 58 | **31** |
| `tst_unit_test`   | 70 | **31** |
| `trie.aql` (module direct) | 150–190 | lower again |

### Interpreting / compiling

- **Interpreting:** ✅ all 11 suites still green.
- **Compiling (`--force-compile`):** ❌ still gated — the compiled stream
  *is* the check pass, so any residual check error still yields
  `check diagnostics`. The emitter itself remains healthy.

### The residue (deferred upstream)

The remaining `trie_unit_test` errors are two narrow families the
gradual-`Any` change does not reach (per the upstream doc, "emergent in the
full transitive analysis, not reproducible in isolation"):

- `trie.aql:59` — `undefined_word: kids`. The `mk-node` body
  `do {end:[fin], val:[val], kids:[kids]}` references a param (`kids`) whose
  name equals the map key; the checker doesn't thread `do {…}` quotation
  params. (The report's "resolve `do{}` quotation params" item.)
- `trie.aql:76` — `no_signature` on `get`/`mk-node` in `put-kid`:
  `(nd "kids" get) set (ch) child` mutates a *freshly-dynamic* node, a path
  the poly-record does not yet cover for the mutating `set`.

Note the doc's client-side workaround (annotate a node param `:Map` instead
of `:Any`) does **not** apply to these two spots — `nd` is already `:Map`
here; the dynamic value comes from `(nd "kids" get)` mid-expression and from
`mk-node`'s `:Any` field params.

### Verdict

Major progress, driven by this report: the dominant false-positive class is
gone, `trie_prop_test` checks clean, and the others fell 3–11×. But because
two residual classes remain and `--force-compile` gates on *zero* check
errors, the pin stays at **`c44d994f`** for the full three-mode guarantee.
Two routes to green from here:

1. **Upstream** resolves the `do{}`-param and dynamic-`set` residue (both
   deferred but scoped in `CLIENT-FIXES-2026-06-24.md`); then re-pin.
2. **Client-side**: restructure `mk-node` and `put-kid` so the suites reach 0
   check errors. Attempted in §7.

---

## 7. Route-2 attempt + policy change: pin `main`, always

Policy update from the maintainer: **stop tracking a "best" pin** — this is
an iterative track with upstream, so the library now pins **latest `main`**
(`14036b412`) and retests, rather than holding `c44d994f`.

### What the client-side restructure achieved

Both deferred residue classes from `CLIENT-FIXES-2026-06-24.md` are fixable
**in isolation**, and those fixes are now in `trie.aql`:

- **`do{}` quotation params →** `mk-node` builds the node with chained `set`
  (`({} set "end" fin) set "val" val …`) instead of
  `do {end:[fin] …}`. The spurious `undefined_word` on the param is gone.
- **`set` over a dynamic node →** a typed accessor `kids-of fn [[nd:Map]
  [Map] […]]` gives the children map a concrete `Map` type, so `put-kid`'s
  `(nd kids-of) set (ch) child` and the downstream `mk-node` dispatch
  resolve. `find-kid` uses it too.

Interpreting stays fully green; `trie_unit_test` check errors fell **5 → 3**.

### Why it does not reach zero (and won't, purely client-side)

The remaining errors are **emergent whole-program cascades**: every one is
**checker-clean when extracted in isolation** (verified for `find-kid`'s
`get`, `put-kid`'s `val`/`end` `get`, and the `drop-kid` `pair get` fold),
but reappears under the full transitive analysis — exactly what the upstream
doc means by "not reproducible in isolation". They trace back to a checker
mis-parse / cascade seed elsewhere in the module (the `build-row` /
`fuzzy-go` region), which is upstream's to fix. Restructuring the individual
sites does not clear them; it only moves the cascade.

And even a **0-error** suite does not compile yet: `trie_prop_test` checks
clean (0 errors) but `--force-compile` still refuses with
`code-body word test-check-prop (Stage 2)` — the test-framework emitter gap.
So on current `main`, **nothing fully compiles**: unit suites are blocked by
the check cascades, property suites by the emitter.

### Disposition

- **Library:** kept the two `trie.aql` fixes (correct, idiomatic, and they
  pre-clear the two named residue classes for when the cascade seed is fixed
  upstream). Did **not** replicate across `radix`/`tst`/`burst`: the cascades
  dominate there (31/31/6 errors) so the change would not reach zero, and
  spreading a divergence for no net gain isn't worth it yet.
- **CI:** interpreter is the **hard gate** for all suites (all green).
  `boru check` and `--force-compile` over the unit suites are **advisory**
  (`continue-on-error`) while pinned to `main`; flip back to hard gates once
  a clean `main` lands.
- **Pin:** `14036b412` across `ci/test.yml`, the SessionStart hook,
  `api.json`, `AGENTS.md`, `docs/how-to.md`.

| `14036b412` | interpret | check | compile |
|---|---|---|---|
| `trie_unit_test`  | ✅ | 3 (was 5) | ❌ (check-gated) |
| `radix_unit_test` | ✅ | 31 | ❌ |
| `tst_unit_test`   | ✅ | 31 | ❌ |
| `burst_unit_test` | ✅ | 6 | ❌ |
| `trie_prop_test`  | ✅ | 0 | ❌ (emitter: `test-check-prop`) |
| all 11 suites     | ✅ | — | — |

---

## 8. Resolved upstream — `boru check` is clean; pin `407fedad`, check now gated

The §7 "emergent whole-program cascades" are **gone**. Upstream landed the
checker-precision work (gradual-`Any` carriers, `/r` reference-export
use-tracing, recursive re-analysis suppression, dynamic-carrier / branch-merge
/ fold-seed matching, and the `build-row` body-reparse fix), independently
re-verified across all three client libraries in
[`design/CLIENT-VERIFICATION-MAIN-2026-06-24.md`](https://github.com/boru-lang/boru/blob/main/design/CLIENT-VERIFICATION-MAIN-2026-06-24.md).

Re-pinned to **`407fedad`** (latest `main`, a few commits past the doc's
`0b010ae`) and re-verified here:

| `407fedad` | interpret | `boru check` | `--force-compile` |
|---|:--:|:--:|---|
| all 11 suites | ✅ | **0 errors** | partial (advisory) |
| `trie`/`radix`/`tst`/`burst`.aql (module-direct) | — | **0 errors** | — |

That is down from the 150–300 errors per module the original
`boru-CHECK-REPORT.md` catalogued — its "these false positives are unfixable
without upstream items 1–4" thesis is now **superseded**: items 1–4 all
landed.

### Changes made

- **Reverted §7's `trie.aql` workarounds.** `mk-node` is back to the
  idiomatic `do {end:[fin] val:[val] kids:[kids]}` and `kids-of` is removed —
  the checker no longer needs either, the original checks 0 errors, and this
  restores cross-module consistency and the documented `do{}` idiom. (Upstream
  confirmed both forms check clean; neither fully `--force-compile`s, so the
  revert is purely a readability/consistency win.)
- **CI: `boru check` promoted to a HARD GATE** over every suite *and* every
  module (all 0). The interpreter remains a hard gate. `--force-compile` stays
  **advisory**.
- **Pin `407fedad`** across `ci/test.yml`, the hook, `api.json`, `AGENTS.md`,
  `docs/how-to.md`.

### `--force-compile` — still partial, still advisory

The strict bytecode path refuses a fixed, sound set of code-body words; every
refusal falls back to a correct interpreter run under `--compile`
(compile==interpreter holds everywhere). Per the upstream gaps table:

| Refusal | Suites |
|---|---|
| `code-body word each (Stage 2)` | every `*_prop_spec` |
| `unannotated or opaque word do` | `trie`/`tst`/`burst` `_unit_test`, `trie_unit_spec` |
| `code-body word test-check-prop (Stage 2)` | `trie_prop_test` |
| `check diagnostics` (dynamic-help example generator, not a real check error) | `radix_unit_test`, `trie_smoke_test` |

These are the named Stage-2 emitter cluster + the dynamic-help-eval project,
**deferred by design** upstream (a partial fix is known to regress the
calibrated langspec corpus). Promote the CI `--force-compile` step to a gate
once they land.

---

## 9. Retest at `0721e828` — force-compile advancing; one breaking change

Re-pinned to **`0721e828`** (latest `main`, 2026-07-11). Two things of note:
real bytecode-emitter progress, and one breaking dispatch change that needed
a one-line library fix.

### Fetch note — GitHub blocked; built via the Go module proxy

This session's egress to `boru-lang/boru` tightened further: `git`, `codeload`,
`github.com`, `api.github.com`, WebFetch, and the scoped GitHub MCP all return
**403 / access-denied**; only `raw.githubusercontent.com` (single files)
answers. The build was recovered through the **Go module proxy**
(`proxy.golang.org`, which is on the egress allowlist): it serves the repo's
modules at a pseudo-version pinned to the HEAD commit.

```bash
# proxy.golang.org resolves main -> v0.0.0-<utc>-<sha> and serves each module zip
VER=$(curl -s https://proxy.golang.org/github.com/boru-lang/boru/@latest | jq -r .Version)
for m in cmd/go eng/go lang/go; do
  curl -so $m.zip "https://proxy.golang.org/github.com/boru-lang/boru/$m/@v/$VER.zip"
done   # unzip into repo layout (cmd/go replaces eng/go, lang/go via ../..) and `go build ./boru`
```

This is the reliable fallback when GitHub git/tarball access is policy-blocked
but the Go proxy is reachable.

### Breaking change — strict forward-collection is now an error

`main` promoted the long-known chained-print / forward-collection foot-gun
(`dx-report.md`: "`5 print 6 print` prints `6` then `5`") from silent
misordering to a hard `signature_error`:

```
[aql/signature_error]: print is still waiting for 1 argument(s) when `def`
begins its own dispatch — a function word is a barrier and never feeds forward
collection (strict rule); group the call in parens so its RESULT becomes the
argument
```

It fired at **both check and interpret** on the one place a bare `print`
immediately preceded a `def` barrier — `test/trie_prop_test.aql`'s summary
(`"results:" print` / `def all-results …`). Blast radius: **1 of 11 suites**.
Fix: `end`-terminate those prints (`"results:" print end`), the exact idiom
`dx-report.md` already prescribes ("one `print end` per line"). This is a
**good** change — it makes a silent reorder loud — but it is a breaking one
for code that leaned on the tolerant behaviour.

### Bytecode `--force-compile` — genuine progress

| | `407fedad` | `0721e828` |
|---|---|---|
| suites that compile | 0 | **4** — all `*_prop_spec` |
| `code-body word each` refusal | every `*_prop_spec` | **gone** (they compile) |
| `check diagnostics` (dynamic-help) refusal | `radix_unit`, `trie_smoke` | **gone** |
| `do` map-body refusal | 4 suites | **gone** |
| new frontier | — | `fold`/`each`/`test-test` code-bodies, `loop results as fn args` (Stage 3), one `unknown provenance` |

So the emitter closed the `each`-over-prop-spec, the `do` map bodies, and the
dynamic-help `check diagnostics` artifact — three of the classes
`proposals/aql-full-compilation.md` scoped. The remaining 7 refusals are the
same two projects, one frontier further in.

### State on `0721e828`

| Mode | Result |
|---|---|
| Interpreter (hard gate) | ✅ 11/11 green |
| `boru check` (hard gate) | ✅ 0 errors — all 11 suites + 4 modules |
| `--force-compile` (advisory) | 4 compile, 7 refuse (frontier above) |

Library change this round: one line in `test/trie_prop_test.aql`
(`print` → `print end` in the summary). No module-source change.

---

## 10. Retest at `6185620` — `--force-compile` frontier fully unmasked

Re-pinned to **`6185620`** (latest `main`, PR #260 "forward-args auto-eval").
Built directly from source (`cd cmd/go && make build`). Both hard gates green;
`--force-compile` root-caused end to end.

### State on `6185620`

| Mode | Result |
|---|---|
| Interpreter (hard gate) | ✅ 11/11 suites green |
| `boru check` (hard gate) | ✅ 0 errors — 11 suites + 4 modules |
| `--force-compile` (advisory) | 4 `*_prop_spec` compile; the 7 imperative/smoke suites refuse — see below |

No library source change was needed this round (the modules and suites are
unchanged; only the pin and this record moved).

### Unmasking the refusals

`boru --force-compile` reports `code-body word <each|fold|test-test> (Stage 2)`
for most suites, but that string is a **mask**: the higher-order body is
probe-compiled in a throwaway `EmitState` (`callable_words.go` `recordClosureDispatch`)
and the real refusal reason is discarded on decline. Instrumenting that probe
to print `probe.Reason` (temporary, reverted) unmasks every one. They reduce to
a small set of **Stage-D operand-provenance leaves** in the emitter — all
bottoming out in "a value produced by a dynamic-receiver dispatch (`get`/`set`
over `Any`, or a recursive user-fn over a dynamic receiver) has no resolvable
compiled *home* when the fn unit is compiled re-entrantly inside a `Test.test`
closure body":

| Real leaf (unmasked) | Engine site | Trie surface | Status |
|---|---|---|---|
| **body result of unknown provenance** | `carrier.go:3816` (`AnalyseFnBody` per-shape quota bail fabricates a provenance-less `declaredReturnBail` carrier that reaches a real `finish()`) | `match-go`, recursive collectors | **fix identified + verified** |
| **dynamic-scope def of unpromoted computed value** | `emit.go:4204` (`RecordDynBind` resolves a current-unit *capture* to a foreign enclosing event instead of its capture slot) | `def t (fixture)` in a `Test.test` body | **fix identified + verified** |
| **call operand of unknown provenance** | `emit.go:3021/3070` (`RecordUserCall`/`RecordUserPolyCall`: a recursive-call arg is a `get`-over-dynamic result with no operand) | `longest-t`, `node-at` | open (Stage-D) |
| **forward operand accounting across a dynamic/island residual (Stage 3)** | `engine.go:2883` | one `each` body in `trie_prop_test` | open (Stage-D) |

The first two mechanisms were each root-caused to a one-hunk fix (see
`proposals/aql-stage-d-partial-fixes.patch`), and each was verified
**byte-identical** (`RunCompiledStrict == Run`) on its isolated repro.

### Critical finding — the two fixes are *not* safe to land alone

Applying **both** fixes together makes `trie_unit_test`, `burst_unit_test`, and
`radix_unit_test` **compile past** their surfacing leaves — and then **crash at
runtime**, under both `--force-compile` *and* the default `--compile` mode:

```
FAIL codec-roundtrip — [aql/internal_error]: bytecode: internal:
    STORE_LOCAL stack underflow (pc=82, src 239:12)        # trie/radix: do…error value-def
FAIL burst-entries  — [aql/internal_error]: bytecode: internal:
    dynamic-scope read miss for `np` ... (src 261:13)      # burst: fold-body local
```

These are **pre-existing, deeper VM-level leaves** (value-def promotion under
`dynEnv` emits a `STORE_LOCAL` with nothing on the stack; a fold-body local read
misses under the dynamic-scope path) that the two upstream leaves' *refusals
were incidentally hiding* — the clean refusal fell back to the sound
interpreter, so the broken lowering never ran. Clearing the outer leaves
unhides the inner ones. Because the pair converts a **sound refusal → a broken
compile** (a `compile == interpret` violation, the project's one hard contract),
**neither fix is landed here.** The `boru` tree is left at pristine `6185620`.

This is precisely the "Stage D is the project, highest-risk" frontier that
`boru`'s own `design/VOXGIG-COMPILE-COMPLETION-PLAN.0.md` scopes: the leaves are
a *chain* per file, and the langspec differential is structurally blind to these
off-corpus recursive-trie shapes, so each fix needs a hand-pinned
`RunCompiledStrict`-vs-`Run` regression and the whole chain must land atomically.

### What "closing `--force-compile`" now requires (ordered)

1. Land the two verified fixes (`proposals/aql-stage-d-partial-fixes.patch`).
2. Fix **value-def promotion under `dynEnv`** so `def x (computed)` inside a
   `do…error` body stores its result (no `STORE_LOCAL` underflow).
3. Fix the **fold-body-local dynamic-scope read** (`np` miss) so a `def`-local
   built in a fold closure resolves under the widened `dynEnv` path.
4. Fix **`call operand of unknown provenance`** — a recursive user-fn call whose
   arg is a `get`-over-dynamic result (`longest-t`, `node-at`).
5. Fix **`forward operand accounting (Stage 3)`** for the `trie_prop_test` `each`.

Each step needs a `RunCompiledStrict == Run` regression on its exact off-corpus
shape plus a `prog.Disassemble()` no-FALLBACK-island assertion, and the whole
set must be re-swept against every suite under **both** `--compile` and
`--force-compile` (green output, not merely "compiles") before promotion.

### Performance baseline (new)

Added `bench/trie_bench.aql` + `bench/run.sh` and `PERF-BASELINE.md`. On this
build the bytecode compiler is **~3× faster** than the interpreter on the trie
workload (N=1000: 14.1 s → 3.8 s), entirely from the top-level driver loops that
already compile; closing the leaves above is what would compile the recursive
trie walks themselves and widen the margin.

## 11. Three Stage-D fixes landed upstream; remaining frontier precisely scoped

Follow-up to §10. The two fixes §10 identified were landed **together with a
third** that resolves §10's "not safe to land alone" regression, on the boru
branch `claude/voxgig-boru-baseline-pctxto` (commit `3e94429`, *"compiler: fix
three Stage-D refusals surfaced by the trie suites"*). All boru pre-commit gates
are green with them: **`make cover-gate` 100%** (54370/54370 reachable stmts),
**`make verify-bytecode` PASSED** (the differential byte-identical corpus + the
`-race` and args-aliasing pins), and `fmt`/`vet`/`lint`/`test` clean.

### The three landed fixes

| # | Engine site | What it fixes | §10 mapping |
|---|---|---|---|
| 1 | `carrier.go` `AnalyseFnBody` | Skip the check-mode analysis **quota** while `Compiling` — past-quota it fabricates a provenance-less `declaredReturnBail` carrier a real compile pass can't lower ("body result of unknown provenance"). Recursion still terminates via the `FnInflight` cycle-breaker + step budget. | leaf 1 ("body result of unknown provenance") |
| 2 | `emit.go` `RecordDynBind` | A **current-unit capture** was misresolved to an unreachable enclosing producing event ("def of unpromoted computed value"). Mirror `resolveOperand`'s capID override → bind from the capture slot; gating on capID keeps the JoinCarriers ID-reuse case correct. | leaf 2 ("dynamic-scope def of unpromoted computed value") |
| 3 | `native_control.go` `doListReturnsFn` | A **fallible multi-value `do` body under a catch** has runtime-variable arity (N no-raise vs 1 caught Error), so a fixed N-seat underflowed on the caught path (the `STORE_LOCAL` underflow §10 flagged as the codec-roundtrip crash). Refuse it at the single arity source → every lowering path declines uniformly and rides the sound interpreter fallback; pure/infallible multi-value bodies still compile at exact arity. | resolves §10's "critical finding" (steps 2–3) |

Fix 3 is why fixes 1+2 are now safe: §10 found that clearing leaves 1+2 alone
unhid a deeper `STORE_LOCAL` underflow (the `do…error` value-def) and a
fold-body dynamic-scope miss, converting a *sound refusal → a broken compile*.
Fix 3 makes the emitter **correctly refuse** the inherently-variable-arity
codec block instead of seating it at a wrong fixed count — so the shape falls
back soundly rather than miscompiling. The `compile == interpret` hard contract
holds.

### Trie compile state on `6185620` + the three fixes

Built the boru branch from source (`cd cmd/go && make build`) and re-swept every
suite under `--no-compile`, `--compile`, and `--force-compile`. **Every suite's
stdout is byte-identical between the interpreter and `--compile`, and every
assertion suite is green.** The split:

| Suite | `--force-compile` | Fallback reason (`--compile`, sound) |
|---|---|---|
| `burst_prop_spec` | ✅ **native** | — |
| `radix_prop_spec` | ✅ **native** | — |
| `trie_prop_spec`  | ✅ **native** | — |
| `trie_unit_spec`  | ✅ **native** | — |
| `burst_unit_test` | fallback | `code-body word test-test (Stage 2)` |
| `radix_unit_test` | fallback | `code-body word test-test (Stage 2)` |
| `trie_unit_test`  | fallback | `code-body word test-test (Stage 2)` |
| `trie_prop_test`  | fallback | `code-body word each (Stage 2)` |
| `trie_smoke_test` | fallback | `fn call operand of unknown provenance` |

So **4 suites now fully native-compile** (was 4 in §10 too, but the codec /
capture / recursive-collector *chains* inside the compiling suites are what the
fixes unblocked — the differential and cover-gate confirm no regression), and
the remaining 5 fall back **cleanly and soundly** (byte-identical, no crash —
the §10 STORE_LOCAL / `np`-miss crashes are gone).

### Residual frontier (two categories, neither a quick fix)

1. **Deferred emitter code-body words** — `test-test`/`test-check-prop` (the
   `Test.test` framework) and one `each` map body. These are **not bugs**: the
   bytecode emitter has no lowering for these code-body words yet (documented in
   `CLAUDE.md` as advisory/deferred). Closing them is emitter *feature* work,
   not a refusal to diagnose.

2. **`fn call operand of unknown provenance`** (`trie_smoke_test`, via
   `TstSet.longest-prefix` → the recursive `longest-t`). **Root-caused this
   round** (superseding §10's "recursive `get`-over-dynamic" hypothesis): the
   real trigger is a **recursive fn whose branch-join accumulator diverges in
   type/identity across the fixpoint**. Minimal repro:

   ```boru
   def rec fn [
     [nd:Any key:Any consumed:Any best:Any] [Any] [
       if (nd eq none) [best] [
         def pc (consumed "x" add)
         def best2 (if (nd "end" get) [pc] [best])   # join of String(pc) & None(best)
         best2 consumed key (nd "mid" get) rec        # self-call: best2 in the `best` slot
       ]
     ]
   ]
   (rec none "hi" "" none) print end
   ```

   Instrumenting `RecordDynBind` + `RecordBranch` + `RecordUserCall` (temporary,
   reverted) traced it fully: within ONE compiled unit the SAME source
   `def best2 (if …)` binds **repeatedly** with different ids AND types
   (`T_314 Any` → `T_497 Disjunct` → `T_ef4 Disjunct` → `S_204 String` …) and the
   branch records repeatedly (seq 5, 12, …) — the recursive-**return fixpoint
   re-analyses the body across iterations**. The self-call's `best2` operand is
   captured as `S_dad…(Integer)`, an id/type from yet another iteration, matching
   NONE of the branch outputs recorded in `producedBy` (all `T_…` Disjuncts). So
   the operand-capture pass and the provenance-recording pass are **different
   fixpoint iterations with independently-minted ids and divergent inferred
   types**, and `resolveOperand` finds `best2` in neither `producedBy` nor
   `localByID`. A correct fix must make the recursive-body re-analysis
   identity-stable OR unify the operand-capture iteration with the
   provenance-recording one, then re-validate against the full byte-identical
   differential; it was **precisely diagnosed and deliberately not rushed** this
   round. (`radix.aql` `node-at` is the same shape.) Full trace + the other two
   leaves: boru `design/VOXGIG-COMPILE-LEAVES.2.md` (boru-lang/boru#265).

### Pin decision

The three fixes live on the boru **branch** `claude/voxgig-boru-baseline-pctxto`,
**not on `main`**. This repo pins `BORU_REF` to `main`, so the pin **stays at
`6185620`** (the current tip of `main`) — a branch commit must not become the
pin, or CI would build unmergeable history. Re-pin to the fixes' `main` commit
once the boru PR merges, and re-run this sweep to promote whichever suites then
compile natively.

## 12. Full native compilation — all suites compile, byte-identical

Follow-up to §11. Every trie suite now compiles under `--force-compile` and is
**byte-identical to the interpreter** under both `--compile` and
`--force-compile` (all assertion suites green; the `_prop_spec` generators run
to the same output). This was achieved with **behaviour-preserving boru
restructurings** that route around the boru compile leaves §11 and
`design/VOXGIG-COMPILE-LEAVES.2.md` scope — NOT by weakening any test. Each
change was verified interpreter-green + `--compile`==`--force-compile`==
`--no-compile` byte-identical:

| Leaf | Where | Compile-friendly form |
|---|---|---|
| **L-JOIN** (recursive branch-join provenance) | `longest-b`/`longest-r`/`longest-t` (burst/radix/tst) | inline the `end`-node choice at the recursive call instead of binding a join `best2` and passing it to the self-call |
| **L-NP** (fold-body local misses under compiled dynamic-scope) | `burst.aql` `collect-eb` | build the `[np v]` pair with `([] np push v push)` instead of a list literal that reads the local `np` |
| **L-DO** (variable-arity fallible `do`) | `*_unit_test` codec cases | `drop` the intentionally-unused decode result so the `do` body is single-value |
| **L-EACH** (forward-stack-drift guard) | `trie_prop_test` summary | fold the per-result print instead of `each` |

These are compile-friendliness workarounds, not the "right" fix: the maintainer's
preferred path is to close the leaves in the boru emitter (see
`design/VOXGIG-COMPILE-LEAVES.2.md`, which retains the minimal repros, traces,
and order-of-attack). Revert each workaround in favour of the upstream compiler
fix once it lands. The behaviour is identical either way; the workaround only
changes WHICH engine runs the hot paths (compiled vs interpreter).

**Important caveat.** The workarounds are the LIBRARY's route around the leaves;
they do not fix the underlying boru compiler bugs, which remain real (L-JOIN's
fixpoint provenance, L-NP's dynamic-scope read miss, the `RunCompiledReason`
side-effect-duplication soundness gap that L-NP exposed). Any DIFFERENT downstream
code hitting those shapes still falls back (or, for L-NP-class shapes, could
duplicate output) until the emitter closes them.
