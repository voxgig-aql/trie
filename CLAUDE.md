# CLAUDE.md

This repository is the `trie` prefix-tree utilities library, written in AQL —
four interchangeable variants (`trie`, `radix`, `tst`, `burst`), each exporting
a Set and a Map over a shared engine.

## Using the library

See @AGENTS.md for how to call the trie API correctly from AQL — the
forward-dispatch calling convention, the four variants, the persistent/immutable
rebind rule, copy-paste idioms, and the common mistakes to avoid. Every example
there is verified against the pinned `aql` build.

## Working on this repository

- A SessionStart hook (`.claude/settings.json` →
  `.claude/hooks/session-start.sh`) builds `aql` from the pinned commit in
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
- The pin tracks aql **`main`** (latest), not a "known-good" commit — we are
  on an iterative-improvement track with upstream, so always re-pin to the
  newest `main` and retest. Record each retest in `AQL-MAIN-VERIFICATION.md`.
- The four imperative **unit** suites (`*_unit_test.aql`) are kept inside the
  bytecode compiler's lowerable subset (value fixtures, no user-`fn` call /
  `fold` / `each` inside a `Test.test` body). **Interpreter is the hard CI
  gate** for every suite. `aql check` and `aql --force-compile` over the unit
  suites are **advisory** while the pin tracks `main`: current `main` made
  `check` follow imports, so each unit file inherits a few of the library's
  emergent `no_signature` cascades (not reproducible in isolation), which also
  gate `--force-compile`. These are being closed upstream
  (`AQL-MAIN-VERIFICATION.md` §7); flip both CI steps back to hard gates once
  a clean `main` lands. The specs and property suites are loop/`check-prop`-
  driven and run on the interpreter only.
- Known AQL-runtime gotchas observed with the pinned build are in
  `dx-report.md`. The pinned aql commit is single-sourced in `ci/test.yml`
  (`AQL_REF`); a CI job fails if the hook or `api.json` drift from it.
