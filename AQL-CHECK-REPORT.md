# `aql check` on the trie library: a diagnostics report

A record of what the AQL static checker (`aql check`) reports when run over this
library, why those reports are **false positives** on this style of code, and
what (if anything) would make the checker useful here. It backs the decision to
wire `aql check` into CI as an **advisory, non-gating** step (`--soft` +
`continue-on-error`) rather than a hard gate — see `ci/test.yml`.

Verified against `aql` commit `db828ec`. Every example below is **standalone**:
copy it into a `.aql` file, then compare `aql check --soft file.aql` (the
diagnostic) against `aql file.aql` (it runs correctly).

> **Re-run at `958c379b` (2026-06-11):** the checker gained real teeth —
> `uncalled_function` now catches this library's single costliest historical
> bug shape — but the false-positive classes below persist and the
> advisory-only decision stands. See the
> [re-run section](#re-run-at-958c379b-2026-06-11) at the bottom.

---

## TL;DR

`aql check` is a structural type/usage checker. This library is deliberately
**generic and dynamically dispatched**: every node is a plain `Map` walked by
stack-dispatched words, children live in untyped association lists pulled out
with `get` (which returns `Any`), and the public surface is exported **by
reference** (`map-add/r`). The checker can't model any of those three things, so
it emits hundreds of diagnostics on code that the full test suite proves
correct. None of them corresponds to a real defect.

| Module | `no_signature` | `missing_returns` | `unused_def` | `fn_body_error` | `branch_error` |
|---|---:|---:|---:|---:|---:|
| `trie.aql`  | 143 | 71  | 33 | 1 | 1 |
| `radix.aql` | 228 | 109 | 29 | 6 | 5 |
| `tst.aql`   | 297 | 53  | 25 | 1 | 3 |
| `burst.aql` | 197 | 82  | 27 | 7 | 1 |

(Per-file counts from `aql check --soft <module>`. All four modules execute
green across the full suite — see `ci/test.yml`.)

Two of these are *correctness* errors in the checker itself (`fn_body_error`,
`branch_error`): it fails to parse or simulate code that the interpreter runs
without complaint. The rest are *expressiveness* gaps — the checker is sound
only for code more statically typed than this.

---

## How to reproduce

```bash
# One module, advisory mode (always exits 0):
aql check --soft trie.aql

# All four (note: analysis halts early — see "A caveat on multi-file runs"):
aql check --soft trie.aql radix.aql tst.aql burst.aql

# Confirm the same code RUNS correctly:
aql test/trie_test.aql      # ... "all green"
```

`--soft` makes `check` exit `0` regardless of findings; without it, `check`
exits non-zero on any error-level diagnostic.

---

## Issue 1 — `unused_def` on reference-exported words

**The checker says:** `def map-make is never used`.

**Standalone example** (`unused.aql`):

```aql
def map-make fn [ [] [Map] [ {end: false} ] ]
export "Demo" { make: map-make/r }
```

```
$ aql check --soft unused.aql
check: 1:5: [warning] unused_def: def map-make is never used
$ aql unused.aql        # defines Demo.make fine — no error
```

**Why it's a false positive.** `map-make` *is* used — it's the implementation of
`Demo.make`, bound in the export block by reference with the `/r` suffix. The
checker's "is it referenced?" pass doesn't count a `/r` reference-export as a
use, so **every word in the public API is flagged**, precisely because it's
public. In this library that's 25–33 false `unused_def` warnings per module —
one for nearly every exported word (`map-keys`, `set-has`, `map-longest-prefix`,
…), all of which are reachable through their namespace.

**Root cause.** Reference exports (`name/r`) aren't traced as usages.

---

## Issue 2 — `no_signature` on generic words over `Any` values

**The checker says:** `no matching signature for fold; assuming best-fit
candidate for analysis` (also for `get`, `push`, and the module's own recursive
words).

**Standalone example** (`nosig.aql`):

```aql
def kids-count fn [ [node:Map] [Integer] [
  0 (node "kids" get) [ var [[pair acc] acc 1 add ] ] fold
] ]
(kids-count {kids: [["a" 1] ["b" 2]]}) print
```

```
$ aql check --soft nosig.aql
check: 2:34: [error] no_signature: no matching signature for fold; assuming best-fit candidate for analysis
$ aql nosig.aql
2
```

**Why it's a false positive.** Children are stored in an association list and
pulled out with `(node "kids" get)`. Core `get` is typed to return `Any`, so by
the time the value reaches `fold`, the checker sees `fold` applied to `Any`
rather than `List` and can't select a signature. The interpreter has the real
list at runtime and folds it correctly (prints `2`).

This is the single largest category (140–300 per module) because the whole
library is built on this one shape: *get an untyped child list, walk it.* It
also cascades onto the library's **own** recursive words — a self-call whose
receiver came from `get` is `Any`, so the recursive call can't be matched
either:

```aql
def walk fn [ [key:String node:Map] [Any] [
  if ((key size) eq 0) [node] [
    def ch  (key slice 0 1)
    def kid (node ch get)                       # kid : Any
    if (kid eq none) [none] [kid (key slice 1 (key size)) walk]   # walk over Any
  ]
] ]
```

```
check: ... no matching signature for walk; assuming best-fit candidate for analysis
check: ... no matching signature for get;  assuming best-fit candidate for analysis
```

**Root cause.** No flow typing / narrowing through `get`, and `Any` doesn't
unify with a concrete parameter type when selecting an overload. The checker
recovers ("assuming best-fit candidate"), but every such site is still reported
at error level.

---

## Issue 3 — `missing_returns` on core words

**The checker says:** `word size has no declared Returns for matched signature;
assuming Any`.

**Standalone example** (`missret.aql`):

```aql
def grow fn [ [xs:List] [List] [ xs (xs size) push ] ]
(grow [1 2]) print
```

```
$ aql check --soft missret.aql
check: 1:41: [warning] missing_returns: word size has no declared Returns for matched signature; assuming Any
check: 1:47: [warning] missing_returns: word push has no declared Returns for matched signature; assuming Any
$ aql missret.aql
[1, 2, 2]
```

**Why it's a false positive.** Nothing is wrong with the *user* code — these
warnings are about **core words** (`size`, `push`, `get`, `add`, …) whose
built-in signatures carry no declared `Returns` for the checker to read, so it
falls back to `Any` and warns at each call site. Because the library leans on
these primitives constantly, that's 50–110 warnings per module describing a gap
in the *standard library's* type annotations, not in this code.

**Root cause.** Core/native word signatures lack `Returns` declarations.

---

## Issue 4 — `fn_body_error`: the checker mis-parses a valid body

**The checker says:** `fn body analysis error for build-row:
[aql/syntax_error]: unmatched opening parenthesis`.

**Standalone example** (`fnbody.aql`) — this is the real `build-row` from
`trie.aql` (Levenshtein DP row), self-contained:

```aql
def min3 fn [ [a:Integer b:Integer c:Integer] [Integer] [
  def m (if (a lt b) [a] [b]) if (m lt c) [m] [c] ] ]

def build-row fn [
  [prow:List query:String letter:String] [List] [
    def cols ((query size) 1 add)
    def row0 [ ((prow get 0) 1 add) ]
    row0 (range 1 cols) [
      var [[i row]
        def insc ((row  get ((i 1 sub))) 1 add)
        def delc ((prow get (i))         1 add)
        def qc   (query slice (i 1 sub) i)
        def repc ((prow get ((i 1 sub))) (if (qc letter eq) [0] [1]) add)
        row (insc delc repc min3) push
      ]
    ] fold
  ]
]

("x" "ax" [0 1 2] build-row) print
```

```
$ aql check --soft fnbody.aql
check: [error] fn_body_error: fn body analysis error for build-row: [aql/syntax_error]: unmatched opening parenthesis
$ aql fnbody.aql
[1, 1, 1]
```

**Why it's a false positive — and worse than the others.** This is not an
expressiveness gap; it's a **checker bug**. The parentheses are balanced (the
interpreter parses and runs the function, printing `[1, 1, 1]`). The checker's
*own* body re-parser — distinct from the one the runtime uses — chokes on the
combination of nested parenthesised arithmetic, a list literal holding a
parenthesised expression, and an inline `if` inside a `fold`/`var` block, and
reports a syntax error that does not exist. When this fires, that function's
body is dropped from analysis entirely.

---

## Issue 5 — `branch_error`: simulated-stack desync

**The checker says:** `branch analysis error: [aql/halt]: undefined stack entry
at position 1`.

**Where it shows up.** In the recursive insert/delete/descent words that branch
with `if` and return a node from one arm and a different shape from the other
(`radix.aql` shows 5, `tst.aql` 3). It carries no source location.

**Why it's a false positive.** It's a **downstream cascade** from Issue 2. Once
`no_signature` forces the checker to "assume a best-fit candidate," its
simulated operand stack can diverge from the real one; a later `if` then tries
to read a stack slot the checker no longer believes exists, and the branch
analysis halts with `undefined stack entry`. The interpreter, working with real
values, never sees this. So `branch_error` is not an independent finding — it's
the checker losing its place after Issue 2, and it disappears wherever the
generic `get`/`fold` shapes don't appear.

---

## A caveat on multi-file runs

Running all four modules in one invocation reports only ~145 errors total —
*fewer* than `trie.aql` alone in some categories — because analysis **halts
early**: after the `fn_body_error`/`branch_error` in the first file the run
emits `check: (empty stack)` and stops fully analysing the rest. Per-file runs
(the table above) are therefore the accurate measure; the combined summary line
under-counts. This is itself a reason not to gate on `check`: its output isn't
even stable across invocation shapes.

```
$ aql check --soft trie.aql radix.aql tst.aql burst.aql | tail -1
check: (empty stack)
```

---

## Net assessment

Of the five categories:

- **Issues 1–3** (`unused_def`, `no_signature`, `missing_returns`) are
  *expressiveness gaps* — the checker is sound only for code that is more
  statically typed than a generic, `Map`-and-association-list trie. They are
  100% false on this library.
- **Issues 4–5** (`fn_body_error`, `branch_error`) are *checker defects* — it
  fails to parse or simulate code the interpreter executes correctly.

There is **no configuration** (short of `--soft`) that filters these down to a
true-positive set, and no subset of the diagnostics that flags a real bug here.
A hard `aql check` gate would block every green build on noise. That is why CI
runs it `--soft` + `continue-on-error`: the log is there for a human to skim,
and the **runnable test suites remain the real gate**.

We re-run `aql check` on each aql bump; if a future release narrows `get`,
traces `/r` exports, ships `Returns` for core words, and fixes the body
re-parser, the signal-to-noise may flip and the step can be promoted to a gate.

---

## What would make `aql check` useful on this code

In rough priority order:

1. **Trace `/r` reference-exports as usages** — kills Issue 1 outright.
2. **Declare `Returns` for core/native words** (`get`, `size`, `push`, `add`,
   `slice`, `fold`, …) — kills Issue 3 and sharpens Issue 2.
3. **Flow-narrow `get` / accept `Any` against concrete params** when selecting
   overloads (or treat `Any` as unifying) — collapses Issue 2 and, with it, the
   Issue 5 cascade.
4. **Fix the body re-parser** so it accepts the same syntax the runtime does —
   removes Issue 4 and the early-halt in multi-file runs.
5. **Demote unresolved generics to `info`**, not `error`, so `--soft` isn't the
   only way to keep exit codes meaningful.

---

## Re-run at `958c379b` (2026-06-11)

The library was upgraded (and refactored — children are now computed-key
Maps enumerated via `StructUtil.items`, and every namespace gained
`decode`) and `aql check --soft` was re-run per module on the new code.
(The standalone examples above were written at `db828ec`; to reproduce
them today, rename their `node` bindings — `node` is now a reserved
built-in word.)

| Module | `no_signature` | `missing_returns` | `unused_def` | `fn_body_error` | `branch_error` | `undefined_word` | `mixed_form_call` (info) |
|---|---:|---:|---:|---:|---:|---:|---:|
| `trie.aql`  | 128 | 70 | 34 | 0 | 1 | 1 | 19 |
| `radix.aql` | 236 | 98 | 29 | 6 | 5 | 5 | 18 |
| `tst.aql`   | 356 | 61 | 24 | 1 | 3 | 0 | 21 |
| `burst.aql` | 193 | 93 | 26 | 7 | 1 | 6 | 20 |

**What improved.** The checker gained three diagnostics with real teeth —
and one of them, `uncalled_function`, is precisely the linter rule this
library's DX report asked for. A wrong-arg-order namespace call is now
flagged at the exact site, with the argument types it saw:

```
$ aql check --soft wrongorder.aql
check: [error] uncalled_function: call to 'map-get' matched no signature
       and was left on the stack as data (arguments: ProperString, Map)
```

This catches the single costliest bug shape in the library's history (the
silently-undispatched namespace word). The companion runtime check (an
`[aql/uncalled_function]` raise at the end-of-run drain) covers leftover
residue, though a *consumed* residue — the original symptom, where `print`
interpolates the function value — is still runtime-silent; the checker is
the tool that sees it. Reason enough to keep running `aql check` on every
change even though it cannot gate.

**What's unchanged.** All five false-positive classes from the original
report persist on this code, in similar volume — `no_signature` on every
`Any`-typed `get`/fold shape (tst's count *grew* with the engine's richer
candidate exploration), `missing_returns` for core words without declared
`Returns`, `unused_def` for every `/r` reference-export, `fn_body_error`
on bodies the runtime parses fine, and the `branch_error` cascade. The
multi-file invocation still halts early (`check: (empty stack)`, reporting
~134 errors where per-file runs find ~900), so per-file runs remain the
accurate measure.

**New noise, small.** Two additions on the noise side of the ledger:

- `undefined_word` errors (1–6 per module) on names the runtime resolves
  fine: a constructor parameter referenced inside a `do {…}` quotation
  (`kids` in `mk-node`), a `def` local inside an `if` arm (`midkids`), and
  the mutually-recursive `b-burst`/`b-insert` pair. All false.
- `mixed_form_call` info advisories (~20 per module) recommending the
  all-forward form for three-plus-argument calls that mix stack and
  forward collection. On this codebase that shape is the deliberate
  receiver-first convention (`t key val …`), so the advisories are noise
  here — but info-severity noise, which is the right severity.

**Verdict unchanged.** With ~900 error-level diagnostics across four
modules that the full suite proves correct, there is still no
configuration that yields a gateable true-positive set. CI keeps the
advisory `--soft` + `continue-on-error` step. Of the original wishlist,
item 5's spirit arrived (`mixed_form_call` ships as info, not error), and
`uncalled_function` is a genuine, load-bearing win; items 1–4 (trace `/r`
exports, core `Returns`, `Any`-unification, body re-parser) remain the
gap between "advisory" and "gate".
