# Using the trie library (agent guide)

Guidance for an AI coding agent **using** this AQL trie library (in this repo or
a downstream project) and **extending** it. Human docs: `README.md`, `docs/`
(Diátaxis), full signatures in `docs/reference.md`, machine-readable API in
`api.json`, design notes and AQL foot-guns in `DX-REPORT.md`.

This library is **pure core AQL** — the four modules import no `aql:*`
dependencies. Verified against `aql` commit `b6617dd`.

---

## Getting the library into a project

**Vendor (simplest).** Copy the four module files (`trie.aql`, `radix.aql`,
`tst.aql`, `burst.aql`) into the consumer project, e.g. `lib/trie/`, then:

```aql
import "./lib/trie/trie.aql"
```

Imports resolve **relative to the working directory** (where you invoke `aql`),
*not* the importing file — so run `aql` from the project root and write paths
relative to it.

**Registry.** If published: `aql install trie-<version>`, then `import "trie"`
loads the package `main` (`trie.aql` → `TrieMap`/`TrieSet`); import other
variants by their file.

Each module is self-contained — vendor only the variant(s) you use.

---

## Calling convention (read this first)

- **Prefer forward arguments.** When a word takes its arguments directly after
  it, write them that way and skip the terminator: `import "./trie.aql"`, not
  `"./trie.aql" import end`.
- **Receiver first for the trie words:** `t key value TrieMap.set end`. These
  namespace calls look ahead for arguments, so **terminate them** with `end`
  (or wrap in parens) — otherwise the word swallows the next token.
  `(t "x" TrieSet.has)` and `t "x" TrieSet.has end` are equivalent.
- **Tries are immutable.** `add` / `set` / `delete` return a *new* trie and
  leave the input unchanged — **always rebind the result**:

  ```aql
  def t1 (t0 "cat" TrieSet.add end)   # t0 is unchanged; use t1
  ```

---

## Pick a variant (all share one API)

| Variant (file) | Namespaces | Use when |
|---|---|---|
| standard trie (`trie.aql`) | `TrieSet` / `TrieMap` | the default; also the only one with `within`/`match` |
| radix / PATRICIA (`radix.aql`) | `RadixSet` / `RadixMap` | long, sparse keys — fewer nodes |
| ternary search tree (`tst.aql`) | `TstSet` / `TstMap` | large/Unicode alphabets |
| burst / HAT (`burst.aql`) | `BurstSet` / `BurstMap` | flat, cache-friendly buckets |

The variants are behaviourally identical (the property suite cross-checks them);
**start with the standard trie.**

---

## Essential patterns (copy-paste, runnable)

```aql
import "./trie.aql"

# Build a set from a list of keys (fold; each add returns the next trie).
# fold runs `init list [body] fold`; the body gets each key `w` and the
# accumulator `acc`, and returns the next trie.
def words ["apple" "app" "apply" "banana"]
def s ((TrieSet.make end) words [ var [[w acc] acc w TrieSet.add end ] ] fold)

# Membership.
(s "app" TrieSet.has end) print            # => true
(s "ap"  TrieSet.has end) print             # => false  (a prefix is not a member)

# Autocomplete: every key under a prefix, sorted.
(s "app" TrieSet.with-prefix end) print     # => ["app", "apple", "apply"]

# Longest stored key that prefixes a query.
(s "applesauce" TrieSet.longest-prefix end) print   # => "apple"

# Delete (rebind; keys below the deleted one survive).
def s2 (s "app" TrieSet.delete end)
(s2 "app"   TrieSet.has end) print           # => false
(s2 "apple" TrieSet.has end) print           # => true

# Map: bind values (any type) to keys.
def m (((TrieMap.make end) "GET" 1 TrieMap.set end) "POST" 2 TrieMap.set end)
(m "GET"    TrieMap.get end) print           # => 1
(m "DELETE" TrieMap.get end) print           # => None  (absent — not an error)
(m TrieMap.entries end) print                # => [["GET" 1] ["POST" 2]]  (sorted)

# Fuzzy (edit-distance) and wildcard search — STANDARD TRIE ONLY.
(s "aple" 1 TrieSet.within end) print        # keys within Levenshtein distance 1
(s "ap*"  TrieSet.match end) print            # `?` = one char, `*` = any run

# Persist + rebuild (there is no string `decode`).
def snapshot (m TrieMap.entries end)         # serialize these however you like
def m2 (snapshot TrieMap.from-entries end)   # …and rebuild later  (sets: keys + from-keys)
```

---

## API at a glance

`Set` namespaces (`TrieSet`, `RadixSet`, `TstSet`, `BurstSet`):

`make` · `add` · `has` · `delete` · `with-prefix` · `longest-prefix` · `keys` ·
`size` · `height` · `from-keys` · `encode`

`Map` namespaces (`TrieMap`, `RadixMap`, `TstMap`, `BurstMap`):

`make` · `set` · `get` · `has` · `delete` · `keys-with-prefix` ·
`entries-with-prefix` · `longest-prefix` · `keys` · `values` · `entries` ·
`size` · `height` · `from-entries` · `encode`

`TrieSet`/`TrieMap` add `within` (fuzzy) and `match` (wildcard).

Exact call-forms, arg order, and return types: `api.json` (structured) and
`docs/reference.md` (prose).

---

## Rules the agent MUST follow

1. **Rebind** the result of `add`/`set`/`delete` — tries never mutate in place.
2. **Receiver-first** argument order for the trie words: `t key value Map.set
   end`, and **terminate** these calls with `end` or parens.
3. **Prefer forward arguments** for words that take them directly — write
   `import "./trie.aql"`, not `"./trie.aql" import end`.
4. `keys`, `values`, `entries`, `with-prefix`, `keys-with-prefix` are **sorted**.
5. `get` returns `none` and `has` returns `false` for an absent key — never an
   error. Use `has` to tell "absent" from "present with value `none`".
6. `within` / `match` exist on **`TrieSet`/`TrieMap` only**. For another
   variant, pull its `keys`/`entries` and rebuild a `TrieSet`/`TrieMap`.
7. There is **no string `decode`**. Round-trip via `keys`+`from-keys` or
   `entries`+`from-entries`.
8. An **empty `TstSet`/`TstMap` is `none`**, not a Map — only relevant if you
   inspect the raw trie value rather than calling namespace words.
9. To compare two key lists, use `assert.equal` (deep) or compare element-wise —
   **AQL's `eq` on lists is identity, not structural** (`["a"] ["a"] eq` is
   `false`).

---

## Verifying your code

Build/locate `aql`, then run a scratch script or the suites:

```bash
aql path/to/your_script.aql        # run your code
aql test/smoke.aql                  # library smoke demo across all variants
for f in test/*.aql; do aql "$f"; done   # full suite (each ends "all green")
```

In this repo a SessionStart hook (`.claude/settings.json` → `ci/setup.sh`)
builds `aql` from the pinned commit if needed and runs the smoke check, so a
fresh session is ready to verify.

---

## Extending the library (contributors)

Read `DX-REPORT.md` for the full account; the load-bearing AQL traps are:

- **Never `merge` to update a node** — `merge` is a *deep, index-wise* merge and
  fuses sibling lists. Rebuild nodes with the explicit `mk-*` constructor.
- **Box stored values** — `do {k: [v]}` *evaluates* map values, so a string
  value like `"if"`/`"do"` would be dispatched as a word. Values are wrapped in
  a one-element list and unwrapped on read.
- **Signature order = reverse of call order** (first parameter = top of stack),
  and a namespace word whose top-of-stack type doesn't match **fails silently**
  (returns the function as data). Write the intended call form in a comment.
- **Reserved binding names:** `end`, `node`, `eq`, and single capital letters
  (type names) cannot be `def`/param/`var` names.
- **Index lists as `xs get (i)`**, not `xs get i` (a bare variable index returns
  `none`).
- **Build path strings with `concat`**, not string interpolation, inside
  recursive-call arguments.
- **`fold` binds `[element accumulator]`** (element first, accumulator on top).

To add a variant: mirror an existing module's structure, export a `…Set` and a
`…Map`, add `test/<variant>_test.aql` plus `test/<variant>_prop_spec.aql` (keep
the trie-equivalence cross-check), and add the new suites to `ci/test.yml`.
