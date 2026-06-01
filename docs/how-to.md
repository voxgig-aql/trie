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
- [Use a trie from your own script](#use-a-trie-from-your-own-script)
- [Run the tests](#run-the-tests)

---

## Install and run aql

The library is written in AQL, which has no tagged release, so build the
interpreter from source (the documented `go install …/aql@latest` fails on
the repo's replace directives):

```bash
git clone https://github.com/aql-lang/aql /tmp/aql-source
cd /tmp/aql-source/cmd/go
GOFLAGS=-mod=mod go build -o "$HOME/.local/bin/aql" ./aql
```

Put `$HOME/.local/bin` on your `PATH`, then check and run:

```bash
aql -version
aql test/smoke.aql
```

This library is verified against aql commit `b6617dd`; the CI workflow
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
"./trie.aql" import end

def words ["apple" "app" "apply" "banana"]
def t ((TrieSet.make end) words [ var [[w acc] acc w TrieSet.add end ] ] fold)
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
def t (((( TrieSet.make end) "app" TrieSet.add end) "apple" TrieSet.add end) "apply" TrieSet.add end)
(t "app" TrieSet.with-prefix end) print     # => ["app", "apple", "apply"]
(t "z"   TrieSet.with-prefix end) print     # => []
```

An empty prefix returns all keys. To autocomplete *and* show values, use
`Map.entries-with-prefix`.

---

## Do longest-prefix matching

Find the longest stored key that is a prefix of a query — e.g. dictionary
tokenization or routing:

```aql
def t ((( TrieSet.make end) "car" TrieSet.add end) "card" TrieSet.add end)
(t "cartoon" TrieSet.longest-prefix end) print   # => "car"
(t "zebra"   TrieSet.longest-prefix end) print   # => None
```

`none` means no stored key prefixes the query.

---

## Use it as a map

Swap `…Set` for `…Map`, and bind values with `set`:

```aql
"./trie.aql" import end

def m (((TrieMap.make end) "GET" 1 TrieMap.set end) "POST" 2 TrieMap.set end)

(m "GET"    TrieMap.get end) print     # => 1
(m "DELETE" TrieMap.get end) print     # => None  (absent)
(m TrieMap.entries end)      print     # => [["GET" 1] ["POST" 2]]
```

Values may be any type, including Strings that happen to be AQL words
(`"if"`, `"do"` …). Use `has` if you need to tell an absent key from a key
whose stored value is `none`.

---

## Delete keys

`delete` returns a new trie without the key, and preserves keys that sit
below it:

```aql
def t ((( TrieSet.make end) "car" TrieSet.add end) "card" TrieSet.add end)
def t2 (t "car" TrieSet.delete end)
(t2 "car"  TrieSet.has end) print     # => false
(t2 "card" TrieSet.has end) print     # => true   (survives)
(t  "car"  TrieSet.has end) print     # => true   (original unchanged)
```

Deleting an absent key is a no-op.

---

## Switch between variants

The API is identical across variants, so switching is mechanical: change
the import and the namespace prefix. From standard to ternary search tree:

```diff
- "./trie.aql" import end
- def t ((TrieSet.make end) "cat" TrieSet.add end)
+ "./tst.aql" import end
+ def t ((TstSet.make end) "cat" TstSet.add end)
```

Every word (`add`, `has`, `with-prefix`, `longest-prefix`, `keys`, …)
keeps its name and behaviour. The property suite cross-checks each variant
against the standard trie, so the swap is safe.

---

## Serialize a trie

`encode` produces a jsonic-style snapshot string — kind, size, and the
sorted keys (sets) or entries (maps) — for logging or inspection:

```aql
def t (((TrieMap.make end) "a" 1 TrieMap.set end) "b" 2 TrieMap.set end)
(t TrieMap.encode end) print
# => {entries:[['a' 1] ['b' 2]] kind:'triemap' size:2}
```

There is no string `decode` (AQL exposes no jsonic-string parser). For a
programmatic round-trip, extract the data and rebuild it:

```aql
def keys (t TrieSet.keys end)        # serialize these however you like
def t2   (keys TrieSet.from-keys end)  # …and rebuild later
```

For a map use `entries` with `Map.from-entries`. `from-keys`/`from-entries`
are available on every variant.

## Fuzzy and wildcard search (standard trie)

The standard trie adds two advanced queries. **Fuzzy** search returns every
key within a Levenshtein edit distance:

```aql
def t (((TrieSet.make end) "cat" TrieSet.add end) "car" TrieSet.add end)
(t "cat" 1 TrieSet.within end) print   # => ["car", "cat"]
```

**Wildcard** search matches a pattern where `?` is any single character and
`*` is any run of characters:

```aql
(t "ca?" TrieSet.match end) print      # => ["car", "cat"]
(t "*t"  TrieSet.match end) print       # => ["cat"]
```

Both work on `TrieMap` too (returning keys). To run them over data held in
another variant, extract its `keys`/`entries` and rebuild a `TrieSet`
/`TrieMap` with `from-keys`/`from-entries`.

---

## Use a trie from your own script

Import the variant by relative path; you do **not** need to import
anything else — each module pulls in its own dependencies:

```aql
"./radix.aql" import end
def t (RadixSet.make end)
# … use the RadixSet namespace …
```

Every call must end with `end` (or be wrapped in parens) so the word
doesn't swallow the following token. `test/smoke.aql` is a complete worked
example you can copy from.

---

## Run the tests

Each variant ships a unit suite and a property suite; the standard trie
additionally has a second property suite exercising the imperative
`test.check-prop` driver:

```bash
aql test/trie_test.aql         # unit tests (standard trie)
aql test/radix_test.aql        # unit tests (radix)
aql test/tst_test.aql          # unit tests (ternary search tree)
aql test/burst_test.aql        # unit tests (burst trie)

aql test/trie_prop_spec.aql    # property tests — declarative spec form
aql test/trie_pbt.aql          # property tests — direct test.check-prop form
aql test/radix_prop_spec.aql   # property tests (radix, with trie cross-check)
aql test/tst_prop_spec.aql     # property tests (tst,   with trie cross-check)
aql test/burst_prop_spec.aql   # property tests (burst, with trie cross-check)
```

Each file ends by asserting `test.fail-count` is `0`, so a failure makes
`aql` exit non-zero — which is what the [CI workflow](../ci/test.yml)
checks on every push and pull request.
