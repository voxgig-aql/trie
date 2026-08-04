# Close the `--force-compile` coverage gap for client libraries

> **Provenance.** Surfaced by the `boru`-main verification track for this library
> (`boru-MAIN-VERIFICATION.md`, §6–§8). As of `boru main @ 407fedad` the
> interpreter and `boru check` are fully green (0 errors) on all 11 suites and
> all 4 modules; the **strict bytecode path (`--force-compile`)** is the only
> remaining non-green path. This is a prompt/brief to direct work **in the
> `boru-lang/boru` repo** (not this library) to close that gap.

---

## Goal (north star)

Make **`boru --force-compile`** (the strict bytecode path — require the VM,
refuse rather than fall back) succeed on **every test suite of the three
reference client libraries** — `voxgig-boru/trie` (11 suites),
`voxgig-boru/decision`, `voxgig-boru/bloom-filter` — with **zero refusals**,
while preserving every existing soundness invariant. "Done" = each suite runs
to completion on the VM and its residual is byte-identical to the interpreter's.

This is purely a **compiler-coverage** effort. The checker is already clean
(every suite and module `boru check`s 0 errors as of `main @ 407fedad`); the
interpreter and `--compile` (best-effort, with fallback) are fully green. Only
the strict path refuses.

## Context / required reading

- `design/COMPILABLE-SUBSET.md` — the positive spec of what lowers and the
  refusal taxonomy (`EmitState.RecordCall`, `isInertConst`, `layoutOperands`).
  This is the contract you are widening; update it in lockstep.
- `design/aql-bytecode-completion.0.md` — the named **Stage-2 code-body**
  emitter cluster (the bulk of the work below).
- `design/module-fn-checkstate-ownership.{5,6}.md` — the diagnosis of the
  "dynamic-help example generator" / `check diagnostics` artifact, including
  three partial fixes that each regressed the calibrated corpus. Read before
  touching that path.
- `design/CLIENT-VERIFICATION-MAIN-2026-06-24.md` — the current ledger of
  exactly which suites refuse and why (the table this work must turn all-green).
- Code: `eng/go/{emit,lower,vm,bytecode}.go`; the strict-mode entry
  `lang.(*boru).RunCompiledStrict`; and the error-severity gate in
  `lang/go/aql.go` (the loop that returns `"check diagnostics"`).

## The refusal classes to close (each is currently observed)

Reproduce the exact reasons with the harness below. They fall into two
independent projects.

### Project A — Stage-2 code-body lowering (the bulk)

These are `NoEvalArgs` "code body" words whose body the emitter cannot yet
lower:

1. **`code-body word each (Stage 2)`** — `each`/`fold`/`filter`/`scan` whose
   body is a `var [[…] …]` / lambda block. The `var` splices bindings onto the
   tape; lowering that body to a closure unit + VM seam is the core task.
   (Affects every `*_prop_spec` and the traversal folds.)
2. **`unannotated or opaque word do`** — a `do {key: [expr]}` **computed-value
   map body** (e.g. how trie's `mk-node` builds
   `{end:[fin] val:[val] kids:[kids]}`). Lower the per-key value quotations and
   assemble the map. (Affects several `_unit_test` and `_unit_spec`.)
3. **`code-body word test-test` / `test-check-prop` (Stage 2)** — the
   test-framework driver words (`Test.test`, `Test.check-prop`). Same code-body
   machinery as (1); likely falls out once `each`/`var`-body lowering lands,
   but verify against the framework's own `fn` bodies.

These share one underlying capability: **faithfully lowering a `NoEvalArgs`
body that carries `var`-spliced locals and/or computed sub-expressions into a
closure unit invoked through the VM seam** (`PUSH_CLOSURE` + the driving word).
Build that once; the three surface words should collapse into it.

### Project B — the dynamic-help / `check diagnostics` artifact (separate, higher-risk)

4. **`check diagnostics`** on suites that themselves `boru check` **0 errors**
   (e.g. `radix_unit_test`, `trie_smoke_test`, `decision_smoke`). This is
   **not** a real check error. The compile path's internal check pass runs the
   **dynamic-help example generator** — each registered `fn` body is evaluated
   in check mode against a synthetic `{a:1,b:2}`, and those synthetic dispatch
   failures become error diagnostics that gate `Finalize`.

   Per `module-fn-checkstate-ownership.6.md`, a filter is **not** acceptable:
   the dynamic-help eval is load-bearing twice — it is also the only
   construction-time check of a defined-but-never-called `fn` body, and the
   langspec compilation corpus (~2830 rows) is calibrated to the exact
   diagnostic set it emits. The sound fix is the scoped project named there:
   **(a)** make the help eval **hermetic** (its synthetic-arg dispatch failures
   must not leak into the emit-gating diagnostic set), **(b)** introduce a
   **first-class construction-check pass** to retain the dead-`fn`-body coverage
   that eval currently provides as a side effect, and **(c)** **re-baseline the
   corpus** against the new diagnostic set. Land these together.

## Hard constraints (do not regress)

- **Soundness:** refusal must stay sound; never emit something that could
  diverge. When in doubt, refuse.
- **compile == interpreter:** the residual must be byte-identical to the
  interpreter's `Run` for the same source, the only sanctioned exception being
  the step-budget divergence in `COMPILABLE-SUBSET.md §7`. No new observable
  runtime behavior.
- **Const-pool mutation safety:** do not admit a mutable instance
  (`Array`/`Object`/`Store`) into `isInertConst`; keep
  `bytecode_constbake_test.go` green.
- **No checker regression:** all client suites and modules must still
  `boru check` 0 errors.
- **Keep the corpus honest:** any change to the emitted diagnostic set must
  come with a deliberate, reviewed corpus re-baseline — not a silent delta.

## Acceptance criteria

1. For each of the three client repos, from the repo root:
   `boru --force-compile test/<suite>.aql` exits 0 for **every** suite, with
   **no** `force-compile:` refusal line.
2. `boru --force-compile X` output is byte-identical to `boru X` for every suite
   (extend the harness to diff them).
3. Upstream gates green: `make verify-bytecode` (fmt/vet/lint +
   `compiled_differential_test.go` + `compiled_property_test.go` + `-race` +
   the `aqldebug` lane), plus `bytecode_constbake_test.go`.
4. The langspec corpus differential passes, with any re-baseline reviewed and
   explained.
5. `design/COMPILABLE-SUBSET.md` updated so the new constructs move from the
   refusal taxonomy (§5) to "what compiles" (§3), with the rule each new gate
   defends.

## Suggested order

1. **Project A first** — larger surface but lower risk (no corpus
   calibration). Land the `var`-body/code-body closure lowering; expect
   `each`/`do`/`test-test`/`test-check-prop` to clear together. Re-run the
   harness; most suites should flip green.
2. **Project B second** — the hermetic-help + construction-check +
   corpus-rebaseline project, landed as one reviewed unit. Clears the residual
   `check diagnostics` suites.
3. Update the client repos only by **promoting the advisory `--force-compile`
   CI step to a hard gate** (no library source change is expected); confirm
   against the harness.

## Reproduction harness

```bash
REF=$(curl -fsSL https://api.github.com/repos/boru-lang/boru/commits/main | jq -r .sha)
mkdir -p /tmp/aql && curl -fsSL "https://codeload.github.com/boru-lang/boru/tar.gz/$REF" \
  | tar -xz -C /tmp/boru --strip-components=1
( cd /tmp/aql/cmd/go && GOFLAGS=-mod=mod go build -o /tmp/aql-bin ./boru )

for repo in trie decision bloom-filter; do
  src=/tmp/$repo; mkdir -p "$src"
  curl -fsSL "https://codeload.github.com/voxgig-boru/$repo/tar.gz/main" \
    | tar -xz -C "$src" --strip-components=1
  ( cd "$src" && for f in test/*.aql; do
      /tmp/aql-bin "$f" >/tmp/i.out 2>&1                 # interpreter (reference)
      /tmp/aql-bin --force-compile "$f" >/tmp/c.out 2>&1
      if grep -q 'force-compile:' /tmp/c.out; then
        echo "REFUSE  $repo/$f -> $(grep -o 'force-compile:.*' /tmp/c.out | head -1)"
      elif diff -q /tmp/i.out /tmp/c.out >/dev/null; then
        echo "OK      $repo/$f"
      else
        echo "DIVERGE $repo/$f"   # must never happen — soundness violation
      fi
    done )
done
```

Target end state: every line prints `OK`; zero `REFUSE`, zero `DIVERGE`.
