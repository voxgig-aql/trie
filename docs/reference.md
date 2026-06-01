# Reference

Technical description of the trie utilities' public surface. This page is
information-oriented: it states what each word is, its call form, and what
it returns. For *why* the variants behave as they do, see
[Explanation](explanation.md); for goal-directed recipes, see the
[How-to guides](how-to.md).

The library is four modules, each exporting two namespaces over a shared
engine:

| Module | Set namespace | Map namespace |
|--------|---------------|---------------|
| `trie.aql`  | `TrieSet`  | `TrieMap`  |
| `radix.aql` | `RadixSet` | `RadixMap` |
| `tst.aql`   | `TstSet`   | `TstMap`   |
| `burst.aql` | `BurstSet` | `BurstMap` |

Import the variant you want:

```aql
import "./trie.aql"
import "./radix.aql"
import "./tst.aql"
import "./burst.aql"
```

A consuming script does **not** need to import anything else; each module
pulls in its own dependencies.

---

## Calling convention

Every operation is a forward-dispatched word and must be terminated with
`end` (or wrapped in parentheses) at the call site, e.g.
`t "x" TrieSet.add end` or `(t "x" TrieSet.add)`. Without a terminator the
word collects the following token as an argument. This is general AQL
forward-precedence behaviour, not specific to this library.

The receiver (the trie) is written first and the arguments follow:
`t key value Map.set end`. Keys are Strings; values may be any type.

### Immutability

Tries are **persistent**. `add`, `set`, and `delete` return a *new* trie
and leave the argument unchanged; bind the result:

```aql
def t1 (t0 "a" TrieSet.add end)   # t0 is still whatever it was
```

### The trie value

`make` returns an opaque trie value — treat it as a handle and operate on
it only through the namespace words. (Internally a standard/radix/burst
trie is a `Map` and an empty ternary search tree is `none`; do not rely on
this.)

---

## Set namespaces — `TrieSet`, `RadixSet`, `TstSet`, `BurstSet`

All four expose an identical surface. `Set` below stands for any of them.

### `Set.make`

| | |
|--|--|
| **Call** | `Set.make end` |
| **Returns** | a new, empty trie |

### `Set.add`

Insert a key. Adding a key already present is a no-op (idempotent).

| | |
|--|--|
| **Call** | `t key Set.add end` |
| **Stack in** | the trie, then the key (`String`) |
| **Returns** | a new trie containing `key` |

### `Set.has`

| | |
|--|--|
| **Call** | `t key Set.has end` |
| **Returns** | `Boolean` — whether `key` is a member |

A pure prefix of a stored key is **not** itself a member unless it was
added in its own right (`has "ca"` is `false` after adding only `"cat"`).

### `Set.delete`

Remove a key (a no-op if absent). Keys that sit *below* the deleted key
are preserved.

| | |
|--|--|
| **Call** | `t key Set.delete end` |
| **Returns** | a new trie without `key` |

### `Set.with-prefix`

Every member that begins with `prefix`, sorted. An empty `prefix` returns
all keys; a prefix present in no key returns `[]`.

| | |
|--|--|
| **Call** | `t prefix Set.with-prefix end` |
| **Returns** | `List` of `String` keys |

### `Set.longest-prefix`

The longest member that is a prefix of `key`, or `none` if no member is.

| | |
|--|--|
| **Call** | `t key Set.longest-prefix end` |
| **Returns** | `String` or `none` |

### `Set.from-keys`

Rebuild a set from a list of keys — the inverse of `keys`, so
`(t keys) from-keys` reproduces `t`. This is the data round-trip for
`encode` (AQL exposes no jsonic-string parser, so there is no string
`decode`; serialize `keys` yourself and rebuild with `from-keys`).

| | |
|--|--|
| **Call** | `keys Set.from-keys end` |
| **Stack in** | a `List` of `String` keys |
| **Returns** | a new set containing exactly those keys |

### `Set.keys`

| | |
|--|--|
| **Call** | `t Set.keys end` |
| **Returns** | `List` of all members, sorted ascending |

### `Set.size` / `Set.height`

| | |
|--|--|
| **Call** | `t Set.size end` / `t Set.height end` |
| **Returns** | `Integer` — number of members / structural depth of the tree |

`height` reflects each variant's own shape (see
[Explanation](explanation.md)); compare sizes across variants, not heights.

### `Set.encode`

A one-way jsonic-style snapshot string carrying the kind, size, and sorted
keys. Suitable for logging or inspection; there is no `decode`.

| | |
|--|--|
| **Call** | `t Set.encode end` |
| **Returns** | `String` |

---

## Map namespaces — `TrieMap`, `RadixMap`, `TstMap`, `BurstMap`

A `Map` carries everything a `Set` does (`make`, `has`, `delete`,
`longest-prefix`, `keys`, `size`, `height`, `encode`) with `add` replaced
by `set`, plus the value-oriented words below. `Map` stands for any of the
four map namespaces.

### `Map.set`

Insert or replace the value bound to `key`. Any value type is accepted,
including Strings that happen to name AQL words (e.g. `"if"`, `"do"`).

| | |
|--|--|
| **Call** | `t key value Map.set end` |
| **Stack in** | the trie, the key (`String`), then the value (`Any`) |
| **Returns** | a new trie binding `key → value` |

### `Map.get`

| | |
|--|--|
| **Call** | `t key Map.get end` |
| **Returns** | the bound value, or `none` if `key` is absent |

`none` is also a legal stored value; use `has` to disambiguate "absent"
from "present with value `none`".

### `Map.keys-with-prefix`

Keys beginning with `prefix`, sorted (the map analogue of
`Set.with-prefix`).

| | |
|--|--|
| **Call** | `t prefix Map.keys-with-prefix end` |
| **Returns** | `List` of `String` keys |

### `Map.entries-with-prefix`

| | |
|--|--|
| **Call** | `t prefix Map.entries-with-prefix end` |
| **Returns** | `List` of `[key, value]` pairs for keys under `prefix` |

### `Map.values` / `Map.entries`

| | |
|--|--|
| **Call** | `t Map.values end` / `t Map.entries end` |
| **Returns** | values (in key-sorted order) / `[key, value]` pairs (key-sorted) |

### `Map.from-entries`

Rebuild a map from a list of `[key, value]` pairs — the inverse of
`entries`, so `(t entries) from-entries` reproduces `t`. The data
round-trip for `encode` (see `Set.from-keys` for why there is no string
`decode`).

| | |
|--|--|
| **Call** | `entries Map.from-entries end` |
| **Stack in** | a `List` of `[key, value]` pairs |
| **Returns** | a new map binding each pair |

---

## Advanced queries — standard trie only (`TrieSet`, `TrieMap`)

These two queries are provided on the standard trie, where the
character-per-node structure makes them efficient and idiomatic. Both
return keys, sorted. (For another variant, extract its `keys` and rebuild
a `TrieSet`/`TrieMap` with `from-keys`/`from-entries` to query.)

### `within` — fuzzy (edit-distance) search

Every key within Levenshtein (insert/delete/substitute) distance `k` of
`query`. Implemented by walking the trie carrying one DP row and pruning a
subtree as soon as its whole row exceeds `k`.

| | |
|--|--|
| **Call** | `t query k TrieSet.within end` / `t query k TrieMap.within end` |
| **Stack in** | the trie, the query (`String`), then the budget `k` (`Integer`) |
| **Returns** | `List` of keys within distance `k`, sorted |

```aql
def t (((TrieSet.make end) "cat" TrieSet.add end) "car" TrieSet.add end)
(t "cat" 1 TrieSet.within end) print   # => ["car", "cat"]
```

### `match` — wildcard search

Every key matching a pattern, where `?` matches any single character, `*`
matches any run of characters (including none), and any other character is
a literal.

| | |
|--|--|
| **Call** | `t pattern TrieSet.match end` / `t pattern TrieMap.match end` |
| **Stack in** | the trie, then the pattern (`String`) |
| **Returns** | `List` of matching keys, sorted |

```aql
(t "ca?" TrieSet.match end) print   # => ["car", "cat"]
(t "c*"  TrieSet.match end) print   # => ["car", "cat"]
```

---

## Behaviour shared by all variants

- **Sorted output.** `keys`, `with-prefix`, `keys-with-prefix`, `values`,
  and `entries` return keys in ascending order.
- **No false answers.** `has` is exact: there are no false positives or
  negatives (unlike a bloom filter).
- **Equivalence.** For the same keys, all four variants expose the same
  `keys`, `has`, `with-prefix`, and `longest-prefix` results. They differ
  only in internal shape, memory, and `height`.

## Errors at a glance

| Situation | Result |
|-----------|--------|
| `get`/`has` on an absent key | `none` / `false` (never an error) |
| `delete` of an absent key | returns an equivalent trie (no-op) |
| missing `end` after a call | dispatch error on the following word (add `end` or parens) |

## Complexity (n keys, key length L, alphabet σ)

| Word | Standard / Radix / TST / Burst |
|------|--------------------------------|
| `make` | `O(1)` |
| `add` / `set` / `get` / `has` | `O(L)` per character step (TST adds a per-step BST search; burst adds a bucket scan) |
| `delete` | `O(L)` |
| `with-prefix` / `keys-with-prefix` | `O(L + m)` for `m` matching keys |
| `longest-prefix` | `O(L)` |
| `keys` / `values` / `entries` / `size` / `encode` | `O(total key length)` |
