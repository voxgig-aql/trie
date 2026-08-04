---
name: trie-aql
description: Use when writing or editing boru code that calls this trie / prefix-tree library — TrieSet / TrieMap and the RadixSet/RadixMap, TstSet/TstMap, BurstSet/BurstMap variants (TrieSet.add / has / with-prefix / longest-prefix / within / match, TrieMap.set / get / entries …), or any file that does `import "./trie.aql"` (or radix/tst/burst). Provides the boru forward-dispatch calling convention (which is not C/Python/JS) — the receiver (trie/set/map) is the LAST argument, so forward `TrieSet.add "cat" s` and pipe `s TrieSet.add "cat"` both bind but receiver-first `TrieSet.add s "cat"` misbinds — plus the persistent/immutable rebind rule, the shared Set/Map API across all four variants, verified copy-paste idioms, and fixes for the mistakes agents make most (mutating in place, foreign call syntax, the eq-vs-deq identity trap, reserved names like node/keys).
---

# Calling the trie utilities library (boru)

Fast prefix search, autocomplete, and longest-prefix matching over String
keys, as a **set** of keys or a **map** from keys to values, in four
interchangeable variants. Everything below is verified against `boru @ 6185620`.

## Import

```boru
import "./trie.aql"        # or radix.aql / tst.aql / burst.aql
```

- Paths resolve relative to the **working directory** you run `boru` from, not
  the importing file. Run `boru` from the project root.
- Each module is self-contained — it imports no `boru:*` dependencies.

## Pick a variant (all share one API)

| File | Namespaces | Use when |
|------|------------|----------|
| `trie.aql`  | `TrieSet` / `TrieMap`   | the default; the only one with `within`/`match` |
| `radix.aql` | `RadixSet` / `RadixMap` | long, sparse keys — fewer nodes |
| `tst.aql`   | `TstSet` / `TstMap`     | large/Unicode alphabets |
| `burst.aql` | `BurstSet` / `BurstMap` | flat, cache-friendly buckets |

## The calling rules

- **The receiver (`t`, the trie/set/map) is the LAST argument.** Every public
  word is declared receiver-last (`set-add [key:String t:Map]`,
  `map-set [val:Any key:String t:Map]`). Because it is last, two call shapes
  both bind correctly:
  - **forward (canonical):** `TrieSet.add "cat" s` — key forward, receiver last.
  - **piping:** `s TrieSet.add "cat"` — receiver flows in from the left, key
    forward. Threads through chains and folds.
  Only **receiver-first, all-forward MISBINDS**: `TrieSet.add s "cat"` feeds `s`
  as the key and `"cat"` as the trie → `signature_error`. `TrieMap.set` follows
  the same shape: `TrieMap.set 1 "GET" m` (value, key, receiver-last).
- **Forward arguments have precedence.** A word grabs the tokens after it,
  stops at the next word or a closing paren, else takes what it needs from the
  stack — so a terminator is usually unnecessary: `(s "x" TrieSet.has)`.
- **Tries are persistent (immutable).** `add` / `set` / `delete` return a
  **new** trie; the input is unchanged — **always rebind the result**
  (`def s2 (TrieSet.add "cat" s)`).
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

```boru
import "./trie.aql"

# Forward canonical (key forward, receiver LAST); rebind — tries are immutable.
def s0 (TrieSet.make)
def s1 (TrieSet.add "cat" s0)               # NOT `TrieSet.add s0 "cat"` (misbinds)
(TrieSet.has "cat" s1) print end            # => true

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
| `t.add("x")` / `TrieSet.add(t,"x")` | `TrieSet.add "x" t` | boru has no call/method syntax. |
| `TrieSet.add t "x"` (receiver-first, all-forward) | `TrieSet.add "x" t` (receiver last) or `t TrieSet.add "x"` (pipe) | forward fills `key` first: receiver-first feeds `t` as the key → `signature_error`. |
| reuse `t` after `TrieSet.add "x" t` | rebind: `def t2 (TrieSet.add "x" t)` | tries are persistent; `add` returns a new trie. |
| `merge` to update a node | rebuild with the explicit `mk-*` constructor; `StructUtil.setpath` for one field | `StructUtil.merge` is a **deep, index-wise** merge (nested lists merge by index). |
| `["a"] ["a"] eq` to compare lists | `["a"] ["a"] deq` (structural) or `Assert.equal` | `eq` is **identity**; use `deq` for structural equality of Maps/Lists. |
| `def keys …` / `def node …` | pick a non-reserved name (`ks`, `nd`) | `node keys vals has scan canon eq` are built-in; `boru check` flags the collision with a source position. |
| `within`/`match` on a radix/tst/burst | pull `keys`/`entries`, rebuild a `TrieSet`/`TrieMap` | those queries exist on the standard trie only. |
| expect a string `decode` | round-trip via `keys`+`from-keys` / `entries`+`from-entries` | there is no string decode. |

## By design (not bugs)

- **Immutable, not mutable.** `set`/`add` return a new trie; for a genuinely
  **mutable** Map/List use `flex` (mutable Map) — don't expect `set` to mutate
  in place.
- **`each` is a MAP** — it must yield one value per element. For pure
  side-effects (no result), use `for`.
- **Integer overflow is fail-loud** — 63-bit; an overflow raises
  `integer_overflow` rather than wrapping. Intended.

If the full repo is available, `AGENTS.md`, `api.json` (machine-readable
signatures), and `docs/reference.md` have the complete guide;
`test/trie_smoke_test.aql` is a runnable example across all four variants.
