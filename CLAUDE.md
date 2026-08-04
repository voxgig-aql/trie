# CLAUDE.md

This repository is the `trie` prefix-tree utilities library, written in boru —
four interchangeable variants (`trie`, `radix`, `tst`, `burst`), each exporting
a Set and a Map over a shared engine.

## Using the library

See @AGENTS.md for how to call the trie API correctly from boru — the
forward-dispatch calling convention, the four variants, the persistent/immutable
rebind rule, copy-paste idioms, and the common mistakes to avoid. Every example
there is verified against the pinned `boru` build.

## Working on this repository

- A SessionStart hook (`.claude/settings.json` →
  `.claude/hooks/session-start.sh`) builds `boru` from the pinned commit in
  remote sessions, so a fresh session can run the suites. Locally, build it
  once from source (there is no tagged release and `go install …/aql@latest`
  is blocked by replace directives) — see
  [docs/how-to.md](docs/how-to.md#install-and-run-aql).
- Tests live in `test/`, named `<subject>_<unit|prop>_<test|spec>.aql` plus a
  `trie_smoke_test.aql`: `_test` = imperative (`Test.test`/`Test.check-prop`),
  `_spec` = declarative spec; `unit` = example-based, `prop` = property-based.
  The standard trie ships all four surfaces as the reference; each variant ships
  at least the imperative-unit + declarative-property pair. Each
  assertion-bearing suite ends by asserting `Test.fail-count` is `0` and prints
  `all green`.
- The pin tracks boru **`main`** (latest), not a "known-good" commit — we are
  on an iterative-improvement track with upstream, so always re-pin to the
  newest `main` and retest. Record each retest in `boru-MAIN-VERIFICATION.md`.
- CI gates two ways, both **hard**: the **interpreter** (every suite ends by
  asserting `Test.fail-count` is 0), and **`boru check`** over every suite *and*
  every module (all now 0 errors — the upstream checker-precision work landed,
  retiring the ~150–300 false positives per module that `boru-CHECK-REPORT.md`
  documented). Keep both green. `boru --force-compile` (the strict bytecode
  path) is **advisory** — it still refuses a handful of code-body words
  (`each`/`do` map bodies, the test-framework `test-test`/`test-check-prop`),
  deferred upstream emitter work; `--compile` matches the interpreter on every
  suite. Promote it to a gate once the emitter closes those words. The latest
  retest and the upstream verification it tracks are in
  `boru-MAIN-VERIFICATION.md` (§8) — note that doc and `boru-CHECK-REPORT.md`'s
  "false positives are unfixable" thesis are now **superseded**: upstream fixed
  them.
- Known boru-runtime gotchas observed with the pinned build are in
  `dx-report.md`. The pinned boru commit is single-sourced in `ci/test.yml`
  (`BORU_REF`); a CI job fails if the hook or `api.json` drift from it.
