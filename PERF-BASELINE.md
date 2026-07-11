# Performance baseline — `voxgig-aql/trie`

**Date:** 2026-07-11
**aql:** `main` (built from source; see `AQL-MAIN-VERIFICATION.md` for the exact
commit and build method)
**Harness:** `bench/trie_bench.aql` + `bench/run.sh` (reproducible; no RNG)

This is a **wall-clock baseline** for the trie library so future changes — in
this repo or upstream `aql` — can be measured against a fixed workload. Numbers
are single-run wall time on the session's remote container (shared CPU), so
treat them as *ratios and orders of magnitude*, not absolute constants; re-run
`bench/run.sh` on the target host for local figures.

## Workload

`bench/trie_bench.aql` builds a `TrieSet` of `N` deterministic keys
(`k<i>x<i*7 mod 1000>`) via a `fold`, then exercises the hot paths:

| Phase | Work |
|---|---|
| build | `N` immutable `TrieSet.add`s (fold; each returns the next trie) |
| membership | `N` `TrieSet.has` lookups (full-key trie walks) |
| prefix | 4 `TrieSet.with-prefix` autocomplete collections |
| keys | one full sorted `TrieSet.keys` dump |

## Results — interpreter vs bytecode compiler

Run with `SIZES="500 1000 2000" bench/run.sh`. The compiler (`aql --compile`)
**soundly falls back to the interpreter for the recursive trie module fns that
still refuse** (see `AQL-MAIN-VERIFICATION.md` §compile), yet the compiled
top-level driver loops (the build `fold` and the membership/prefix `each`
sweeps) still deliver a solid speedup:

| N (keys) | interpreter | compiled | speedup |
|---------:|------------:|---------:|:-------:|
| 500 | ~6.7 s | ~2.0 s | ~3.3× |
| 1000 | ~13.5 s | ~4.0 s | ~3.4× |
| 2000 | ~35 s | ~12 s | ~3.0× |

Scaling is roughly linear in `N` (slightly superlinear because `with-prefix`
collects a growing key set). The **~3× compiled speedup comes entirely from the
driver loops**; closing the remaining `--force-compile` refusals in the
recursive module fns (the `body result of unknown provenance` / dynamic-receiver
dispatch frontier catalogued in `AQL-MAIN-VERIFICATION.md`) is the path to
compiling the trie walks themselves and widening this margin.

## Per-suite interpreter runtimes (latest `main`)

Reference cost of the CI suites under the interpreter (`aql <suite>.aql`):

| Suite | ~time |
|---|---|
| `trie_unit_spec` | 0.9 s |
| `tst_unit_test` | 0.9 s |
| `radix_unit_test` | 1.8 s |
| `burst_unit_test` | 1.9 s |
| `trie_unit_test` | 1.9 s |
| `trie_smoke_test` | 5.4 s |
| `trie_prop_test` | 8.4 s |
| `radix_prop_spec` | 18 s |
| `trie_prop_spec` | 37 s |
| `tst_prop_spec` | 38 s |
| `burst_prop_spec` | ~38 s |

The `*_prop_spec` declarative property **generators** dominate — they are the
slow lane in CI (each runs many generated cases). The imperative unit/`_test`
suites are all under ~2 s except the multi-variant `trie_smoke_test`.

## Reproducing

```bash
# from the repo root, with `aql` on PATH
bench/run.sh                       # SIZES defaults to "500 1000 2000"
SIZES="1000" bench/run.sh          # single size
```
