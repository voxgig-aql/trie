---
name: trie-aql
description: Use when writing or editing AQL code that calls this trie / prefix-tree library — TrieSet / TrieMap and the RadixSet/RadixMap, TstSet/TstMap, BurstSet/BurstMap variants (TrieSet.add / has / with-prefix / longest-prefix / within / match, TrieMap.set / get / entries …), or any file that does `import "./trie.aql"` (or radix/tst/burst). Provides the AQL forward-dispatch calling convention (which is not C/Python/JS), the persistent/immutable rebind rule, the shared Set/Map API across all four variants, verified copy-paste idioms, and fixes for the mistakes agents make most (mutating in place, foreign call syntax, the eq-on-lists-is-identity trap).
---

# Calling the trie utilities library (AQL)

Fast prefix search, autocomplete, and longest-prefix matching over String
keys, as a **set** of keys or a **map** from keys to values, in four
interchangeable variants. Everything below is verified against `aql @ db828ec`.

## Import

```aql
import "./trie.aql"        # or radix.aql / tst.aql / burst.aql
```

- Paths resolve relative to the **working directory** you run `aql` from, not
  the importing file. Run `aql` from the project root.
- Each module is self-contained — it imports no `aql:*` dependencies.

## Pick a variant (all share one API)

| File | Namespaces | Use when |
|------|------------|----------|
| `trie.aql`  | `TrieSet` / `TrieMap`   | the default; the only one with `within`/`match` |
| `radix.aql` | `RadixSet` / `RadixMap` | long, sparse keys — fewer nodes |
| `tst.aql`   | `TstSet` / `TstMap`     | large/Unicode alphabets |
| `burst.aql` | `BurstSet` / `BurstMap` | flat, cache-friendly buckets |

## The calling rules

- **Forward arguments have precedence.** A word grabs the tokens after it,
  stops at the next word or a closing paren, else takes what it needs from the
  stack — so a terminator is usually unnecessary: `(t "x" TrieSet.has)`.
- **Receiver first:** `t key value TrieMap.set` — results pipe through chains.
- **Tries are persistent (immutable).** `add` / `set` / `delete` return a
  **new** trie; the input is unchanged — **always rebind the result**.
- **Disambiguate** only when a bare literal immediately follows a stack-form
  call: use parens, a trailing `end`, or the `/s` (force-stack) modifier.

## API at a glance

`…Set`: `make` · `add` · `has` · `delete` · `with-prefix` · `longest-prefix` ·
`keys` · `size` · `height` · `from-keys` · `encode`
`…Map`: `make` · `set` · `get` · `has` · `delete` · `keys-with-prefix` ·
`entries-with-prefix` · `longest-prefix` · `keys` · `values` · `entries` ·
`size` · `height` · `from-entries` · `encode`
`TrieSet`/`TrieMap` add `within` (fuzzy) and `match` (wildcard, `?`/`*`).

`keys`, `values`, `entries`, `with-prefix`, `keys-with-prefix` are **sorted**.
`get` returns `none` / `has` returns `false` for an absent key (never an error).

## Idioms (verified)

```aql
import "./trie.aql"

def s ((TrieSet.make) ["apple" "app" "apply"] [ var [[w acc] acc w TrieSet.add end ] ] fold)
(s "app"  TrieSet.has)             print   # => true
(s "ap"   TrieSet.has)             print   # => false  (a prefix is not a member)
(s "app"  TrieSet.with-prefix)     print   # => ["app", "apple", "apply"]
(s "applesauce" TrieSet.longest-prefix) print   # => "apple"

def m (((TrieMap.make) "GET" 1 TrieMap.set) "POST" 2 TrieMap.set)
(m "GET"    TrieMap.get)     print          # => 1
(m TrieMap.entries)          print          # => [["GET" 1] ["POST" 2]]  (sorted)
```

## Common mistakes

| ✗ Don't | ✓ Do | Why |
|---------|------|-----|
| `t.add("x")` / `TrieSet.add(t,"x")` | `t "x" TrieSet.add` | AQL has no call/method syntax. |
| reuse `t` after `t "x" TrieSet.add` | rebind: `def t2 (t "x" TrieSet.add)` | tries are persistent; `add` returns a new trie. |
| `merge` to update a node | rebuild with the explicit `mk-*` constructor | `merge` is a deep, index-wise merge that fuses sibling lists. |
| `["a"] ["a"] eq` to compare lists | `assert.equal` (deep) or element-wise | `eq` on lists is identity, not structural. |
| `within`/`match` on a radix/tst/burst | pull `keys`/`entries`, rebuild a `TrieSet`/`TrieMap` | those queries exist on the standard trie only. |
| expect a string `decode` | round-trip via `keys`+`from-keys` / `entries`+`from-entries` | there is no string decode. |

If the full repo is available, `AGENTS.md`, `api.json` (machine-readable
signatures), and `docs/reference.md` have the complete guide;
`test/trie_smoke_test.aql` is a runnable example across all four variants.
