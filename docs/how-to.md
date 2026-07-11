# How-to guides

Task-oriented recipes. Each assumes you know roughly what a trie is; if
not, start with the [Tutorial](tutorial.md). For the *why*, follow the
links into the [Explanation](explanation.md); for exact signatures, the
[Reference](reference.md).

- [Install and run aql](#install-and-run-aql)
- [Choose a variant](#choose-a-variant)
- [Build a trie from a list of keys](#build-a-trie-from-a-list-of-keys)
- [Autocomplete a prefix](#autocomplete-a-prefix)
- [Do longest-prefix matching](#do-longest-prefix-matching)
- [Use it as a map](#use-it-as-a-map)
- [Delete keys](#delete-keys)
- [Switch between variants](#switch-between-variants)
- [Serialize a trie](#serialize-a-trie)
- [Fuzzy and wildcard search (standard trie)](#fuzzy-and-wildcard-search-standard-trie)
- [Use a trie from your own script](#use-a-trie-from-your-own-script)
- [Run the tests](#run-the-tests)

---

## Install and run aql

The library is written in AQL, which has no tagged release, so build the
interpreter from source (the documented `go install …/aql@latest` fails on
the repo's replace directives):

```bash
git clone https://github.com/aql-lang/aql /tmp/aql-source
cd /tmp/aql-source
git checkout 0721e8280e01a37174c41b99ab49799f3098c135   # the commit CI pins (ci/test.yml AQL_REF)
cd cmd/go
GOFLAGS=-mod=mod go build -o "$HOME/.local/bin/aql" ./aql
```

Put `$HOME/.local/bin` on your `PATH`, then check and run:

```bash
aql -version
aql test/trie_smoke_test.aql
```

This library is verified against aql commit `0721e828`; the CI workflow
(`ci/test.yml`) pins the same commit.

---

## Choose a variant

All four behave identically through the API; pick by shape:

| Pick | When |
|------|------|
| **standard trie** (`trie.aql`)  | the default — simplest, predictable, one node per character |
| **radix tree** (`radix.aql`)    | keys are long and don't share much — compression saves many nodes |
| **ternary search tree** (`tst.aql`) | the alphabet is large/Unicode — three pointers per node beats a per-node child map |
| **burst trie** (`burst.aql`)    | you want flat, cache-friendly buckets over a shallow trie spine |

When in doubt, start with the standard trie and switch later — it is a
one-line change (see [Switch between variants](#switch-between-variants)).
See [Explanation](explanation.md) for the trade-offs behind each.

---

## Build a trie from a list of keys

Fold the keys into a fresh trie. Each `add` returns the next trie, so the
accumulator threads through:

```aql
import "./trie.aql"

def words ["apple" "app" "apply" "banana"]
def t ((TrieSet.make) words [ var [[w acc] acc w TrieSet.add end ] ] fold)
```

`fold` runs as `init list [body] fold` — here the empty trie is the
initial accumulator and the body receives each key `w` and the
accumulator `acc`, returning the next trie. For a map, carry a value too:
`acc w v TrieMap.set end`.

---

## Autocomplete a prefix

`with-prefix` (set) / `keys-with-prefix` (map) returns every key beneath a
prefix, sorted — exactly an autocomplete list:

```aql
def t (((( TrieSet.make) "app" TrieSet.add) "apple" TrieSet.add) "apply" TrieSet.add)
(t "app" TrieSet.with-prefix) print     # => ["app", "apple", "apply"]
(t "z"   TrieSet.with-prefix) print     # => []
```

An empty prefix returns all keys. To autocomplete *and* show values, use
`Map.entries-with-prefix`.

---

## Do longest-prefix matching

Find the longest stored key that is a prefix of a query — e.g. dictionary
tokenization or routing:

```aql
def t ((( TrieSet.make) "car" TrieSet.add) "card" TrieSet.add)
(t "cartoon" TrieSet.longest-prefix) print   # => "car"
(t "zebra"   TrieSet.longest-prefix) print   # => None
```

`none` means no stored key prefixes the query.

---

## Use it as a map

Swap `…Set` for `…Map`, and bind values with `set`:

```aql
import "./trie.aql"

def m (((TrieMap.make) "GET" 1 TrieMap.set) "POST" 2 TrieMap.set)

(m "GET"    TrieMap.get) print     # => 1
(m "DELETE" TrieMap.get) print     # => None  (absent)
(m TrieMap.entries)      print     # => [["GET" 1] ["POST" 2]]
```

Values may be any type, including Strings that happen to be AQL words
(`"if"`, `"do"` …). Use `has` if you need to tell an absent key from a key
whose stored value is `none`.

---

## Delete keys

`delete` returns a new trie without the key, and preserves keys that sit
below it:

```aql
def t ((( TrieSet.make) "car" TrieSet.add) "card" TrieSet.add)
def t2 (t "car" TrieSet.delete)
(t2 "car"  TrieSet.has) print     # => false
(t2 "card" TrieSet.has) print     # => true   (survives)
(t  "car"  TrieSet.has) print     # => true   (original unchanged)
```

Deleting an absent key is a no-op.

---

## Switch between variants

The API is identical across variants, so switching is mechanical: change
the import and the namespace prefix. From standard to ternary search tree:

```diff
- import "./trie.aql"
- def t ((TrieSet.make) "cat" TrieSet.add)
+ import "./tst.aql"
+ def t ((TstSet.make) "cat" TstSet.add)
```

Every word (`add`, `has`, `with-prefix`, `longest-prefix`, `keys`, …)
keeps its name and behaviour. The property suite cross-checks each variant
against the standard trie, so the swap is safe.

---

## Serialize a trie (and read it back)

`encode` produces a JSON snapshot string — kind, size, and the sorted keys
(sets) or entries (maps) — and `decode` rebuilds a trie from it:

```aql
def t (((TrieMap.make) "a" 1 TrieMap.set) "b" 2 TrieMap.set)
def snapshot (t TrieMap.encode)    # {"entries": [["a", 1], ["b", 2]], "kind": "triemap", "size": 2}
def t2 (snapshot TrieMap.decode)
(t2 "b" TrieMap.get) print          # => 2
```

`decode` is strict about the payload's `kind`: each namespace reads only
its own snapshots and **raises** a catchable error on any other (so a
`radixset` snapshot fed to `TrieMap.decode` fails loudly, not quietly):

```aql
do [ (snapshot RadixMap.decode) ] error [ var [[e]
  (convert String (e "message" get)) print   # names both kinds
] ]
```

To move keys **between variants** — or to serialize some other way — use
the data-level round-trip instead; `from-keys`/`from-entries` accept plain
lists and are available on every variant:

```aql
def keys (t TrieMap.keys)
def r    (keys RadixSet.from-keys)   # same keys, different variant
```

---

## Fuzzy and wildcard search (standard trie)

The standard trie adds two advanced queries. **Fuzzy** search returns every
key within a Levenshtein edit distance:

```aql
def t (((TrieSet.make) "cat" TrieSet.add) "car" TrieSet.add)
(t "cat" 1 TrieSet.within) print   # => ["car", "cat"]
```

**Wildcard** search matches a pattern where `?` is any single character and
`*` is any run of characters:

```aql
(t "ca?" TrieSet.match) print      # => ["car", "cat"]
(t "*t"  TrieSet.match) print       # => ["cat"]
```

Both work on `TrieMap` too (returning keys). To run them over data held in
another variant, extract its `keys`/`entries` and rebuild a `TrieSet`
/`TrieMap` with `from-keys`/`from-entries`.

---

## Use a trie from your own script

Import the variant by relative path; you do **not** need to import
anything else — each module pulls in its own dependencies:

```aql
import "./radix.aql"
def t (RadixSet.make)
# … use the RadixSet namespace …
```

Forward arguments have precedence and a call resolves at the next function
word or paren, so you rarely need a terminator; add `end`, parens, or the
`/s` modifier only to stop a bare following literal from being grabbed.
`test/trie_smoke_test.aql` is a complete worked example you can copy from.

---

## Run the tests

Each variant ships an example-based unit suite and a declarative property
suite. The standard trie additionally ships the other two framework
surfaces — a declarative unit spec and an imperative property suite — so
all four are demonstrated:

```bash
aql test/trie_unit_test.aql    # unit tests — standard trie (direct)
aql test/trie_unit_spec.aql    # unit tests — standard trie (declarative spec)
aql test/radix_unit_test.aql   # unit tests — radix
aql test/tst_unit_test.aql     # unit tests — ternary search tree
aql test/burst_unit_test.aql   # unit tests — burst trie

aql test/trie_prop_spec.aql    # property tests — standard trie (declarative spec)
aql test/trie_prop_test.aql    # property tests — standard trie (direct test.check-prop)
aql test/radix_prop_spec.aql   # property tests — radix (with trie cross-check)
aql test/tst_prop_spec.aql     # property tests — tst   (with trie cross-check)
aql test/burst_prop_spec.aql   # property tests — burst (with trie cross-check)
```

Each file ends by asserting `test.fail-count` is `0`, so a failure makes
`aql` exit non-zero — which is what the [CI workflow](../.github/workflows/test.yml)
checks on every push and pull request.
