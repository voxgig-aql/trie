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
- The four imperative **unit** suites (`*_unit_test.aql`) are kept inside the
  bytecode compiler's lowerable subset and CI gates each three ways:
  interpreter, `aql check` (0 errors), and `aql --force-compile`. Keep them
  that way — no user-`fn` call, `fold`, or `each` inside a `Test.test` body
  (use a shared value fixture; see the fourth review in `DX-REPORT.md`). The
  specs and property suites are loop/`check-prop`-driven and run on the
  interpreter only.
- Known AQL-runtime gotchas observed with the pinned build are in
  `dx-report.md`. The pinned aql commit is single-sourced in `.github/workflows/test.yml`
  (`AQL_REF`); a CI job fails if the hook or `api.json` drift from it.
