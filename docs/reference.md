# Reference

Technical description of the trie utilities' public surface. This page is
information-oriented: it states what each word is, its call form, and what
it returns. For *why* the variants behave as they do, see
[Explanation](explanation.md); for goal-directed recipes, see the
[How-to guides](how-to.md).

> **AI agents:** [AGENTS.md](../AGENTS.md) condenses the calling
> convention, idioms, and common mistakes for machine use.

The library is four modules, each exporting two namespaces over a shared
engine:

| Module | Set namespace | Map namespace |
|--------|---------------|---------------|
| `trie.aql`  | `TrieSet`  | `TrieMap`  |
| `radix.aql` | `RadixSet` | `RadixMap` |
| `tst.aql`   | `TstSet`   | `TstMap`   |
| `burst.aql` | `BurstSet` | `BurstMap` |

Import the variant you want:

```boru
import "./trie.aql"
import "./radix.aql"
import "./tst.aql"
import "./burst.aql"
```

A consuming script does **not** need to import anything else; each module
pulls in its own dependencies.

---

## Calling convention

Operations are forward-dispatched words: a word takes the tokens after it as
arguments, stops at the next function word or a closing paren, and otherwise
draws from the stack — so a terminator is usually unnecessary
(`(t "x" TrieSet.add)` and `t "x" TrieSet.has print` both resolve). The one
case that needs disambiguation is a bare, type-compatible literal immediately
following a call with nothing between; resolve it with parens, a trailing
`end`, or the `/s` modifier, which forces stack-arg resolution. This is general
boru forward-precedence behaviour, not specific to this library.

The receiver (the trie) is the **last** argument in every Set/Map word's
signature, so two call shapes bind: **forward** `Map.set value key t`
(arguments forward, receiver last) and **pipe/stack** `t key value Map.set`
(the receiver flows in from the left — the form used in the Call rows below).
Only receiver-first-forward (`Map.set t key value`) misbinds. Keys are
Strings; values may be any type. The Call rows show a trailing `end` for
clarity; it is optional in the common case above.

### Immutability

Tries are **persistent**. `add`, `set`, and `delete` return a *new* trie
and leave the argument unchanged; bind the result:

```boru
def t1 (t0 "a" TrieSet.add)   # t0 is still whatever it was
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
`(t keys) from-keys` reproduces `t`. This is the *data-level* round-trip,
and the way to move keys **between variants** (`decode` below is strict
about which variant wrote the snapshot; `from-keys` is not).

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

A JSON snapshot string (via `StructUtil.jsonify`) carrying the kind, size,
and sorted keys — `{"kind": "trieset", "size": …, "keys": […]}`. Feed it
back to `decode` to rebuild the set.

| | |
|--|--|
| **Call** | `t Set.encode end` |
| **Returns** | `String` |

### `Set.decode`

The inverse of `encode`: parse a snapshot string and rebuild the set.
Each namespace accepts only its **own** kind (`TrieSet.decode` reads
`"trieset"` payloads, `RadixSet.decode` reads `"radixset"`, …); any other
kind **raises** a catchable error naming both kinds — catch it with
`do […] error […]`. Map namespaces decode their `{kind, size, entries}`
payloads the same way. To move data *across* variants, use
`keys`/`from-keys` (or `entries`/`from-entries`) instead.

| | |
|--|--|
| **Call** | `s Set.decode end` |
| **Stack in** | the snapshot `String` |
| **Returns** | a new trie equal to the encoded one |

```boru
def snapshot (t TrieSet.encode)
def t2 (snapshot TrieSet.decode)     # (t TrieSet.keys) == (t2 TrieSet.keys)
```

A stored `none` value (maps) serialises as JSON `null` and decodes back to
`none` — it compares equal under `eq`/`deq`, though `Assert.equal` still
distinguishes the hydrated value from a `none` literal.

---

## Map namespaces — `TrieMap`, `RadixMap`, `TstMap`, `BurstMap`

A `Map` carries everything a `Set` does (`make`, `has`, `delete`,
`longest-prefix`, `keys`, `size`, `height`, `encode`, `decode`) with `add`
replaced by `set`, plus the value-oriented words below. `Map` stands for
any of the four map namespaces.

### `Map.set`

Insert or replace the value bound to `key`. Any value type is accepted,
including Strings that happen to name boru words (e.g. `"if"`, `"do"`).

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
`entries`, so `(t entries) from-entries` reproduces `t`. The *data-level*
round-trip, and the cross-variant path (`decode` only accepts its own
variant's snapshots).

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

```boru
def t (((TrieSet.make) "cat" TrieSet.add) "car" TrieSet.add)
(t "cat" 1 TrieSet.within) print   # => ["car", "cat"]
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

```boru
(t "ca?" TrieSet.match) print   # => ["car", "cat"]
(t "c*"  TrieSet.match) print   # => ["car", "cat"]
```

---

## Behaviour shared by all variants

- **Sorted output.** `keys`, `with-prefix`, `keys-with-prefix`,
  `entries-with-prefix`, `values`, and `entries` return keys in ascending
  order — by construction: children enumerate in character order, so the
  collectors emit sorted output without a final sort.
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
| `decode` of another variant's (or a malformed) payload | raises a catchable error (`do […] error […]`) |
| missing `end` after a call | dispatch error on the following word (add `end` or parens) |

## Complexity (n keys, key length L, alphabet σ)

| Word | Standard / Radix / TST / Burst |
|------|--------------------------------|
| `make` | `O(1)` |
| `add` / `set` / `get` / `has` | `O(L)` per character step (TST adds a per-step BST search; burst adds a bucket scan) |
| `delete` | `O(L)` |
| `with-prefix` / `keys-with-prefix` | `O(L + m)` for `m` matching keys |
| `longest-prefix` | `O(L)` |
| `keys` / `values` / `entries` / `size` / `encode` / `decode` | `O(total key length)` |
