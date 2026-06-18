# Using the trie library (agent guide)

Guidance for an AI coding agent **using** this AQL trie library (in this repo or
a downstream project) and **extending** it. Human docs: `README.md`, `docs/`
(Diátaxis), full signatures in `docs/reference.md`, machine-readable API in
`api.json`, design notes and AQL foot-guns in `DX-REPORT.md`.

The four modules depend only on the **standard `aql:struct-util` module**
(map enumeration + jsonic parse/serialise), which ships with the interpreter —
no third-party dependencies. Verified against `aql` commit `5aed3834`.

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

- **Forward arguments have precedence.** A word grabs the tokens *after* it as
  arguments, stops at the next function word or a closing paren, and otherwise
  takes what it needs from the stack. So a terminator is usually unnecessary:
  `import "./trie.aql"`, `(t "x" TrieSet.has)`, and `t "x" TrieSet.has print`
  all resolve on their own.
- **Receiver first for the trie words** — a convention that makes results pipe:
  `t key value TrieMap.set`. Each `add`/`set`/`delete` returns a new trie, so
  the receiver threads through chains and folds.
- **Disambiguate only when a bare literal follows a call.** If a type-compatible
  literal sits immediately after a stack-form call with no word or paren
  between, forward-precedence will consume it. Resolve it with parens, a
  trailing `end`, or the **`/s` modifier**, which pins that call to stack args:
  `5 5 cmp/s 9` compares `5` and `5` (leaving `9`), whereas `5 5 cmp 9`
  forward-grabs the `9`.
- **Tries are immutable.** `add` / `set` / `delete` return a *new* trie and
  leave the input unchanged — **always rebind the result**:

  ```aql
  def t1 (t0 "cat" TrieSet.add)   # t0 is unchanged; use t1
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
def s ((TrieSet.make) words [ var [[w acc] acc w TrieSet.add end ] ] fold)

# Membership.
(s "app" TrieSet.has) print            # => true
(s "ap"  TrieSet.has) print             # => false  (a prefix is not a member)

# Autocomplete: every key under a prefix, sorted.
(s "app" TrieSet.with-prefix) print     # => ["app", "apple", "apply"]

# Longest stored key that prefixes a query.
(s "applesauce" TrieSet.longest-prefix) print   # => "apple"

# Delete (rebind; keys below the deleted one survive).
def s2 (s "app" TrieSet.delete)
(s2 "app"   TrieSet.has) print           # => false
(s2 "apple" TrieSet.has) print           # => true

# Map: bind values (any type) to keys.
def m (((TrieMap.make) "GET" 1 TrieMap.set) "POST" 2 TrieMap.set)
(m "GET"    TrieMap.get) print           # => 1
(m "DELETE" TrieMap.get) print           # => None  (absent — not an error)
(m TrieMap.entries) print                # => [["GET" 1] ["POST" 2]]  (sorted)

# Fuzzy (edit-distance) and wildcard search — STANDARD TRIE ONLY.
(s "aple" 1 TrieSet.within) print        # keys within Levenshtein distance 1
(s "ap*"  TrieSet.match) print            # `?` = one char, `*` = any run

# Persist + rebuild: encode/decode round-trip (decode raises a catchable
# error on a payload of the wrong kind).
def snapshot (m TrieMap.encode)          # JSON text — write it anywhere
def m2 (snapshot TrieMap.decode)         # …and rebuild later
# Data-level round-trips also work: keys+from-keys, entries+from-entries.
```

---

## API at a glance

`Set` namespaces (`TrieSet`, `RadixSet`, `TstSet`, `BurstSet`):

`make` · `add` · `has` · `delete` · `with-prefix` · `longest-prefix` · `keys` ·
`size` · `height` · `from-keys` · `encode` · `decode`

`Map` namespaces (`TrieMap`, `RadixMap`, `TstMap`, `BurstMap`):

`make` · `set` · `get` · `has` · `delete` · `keys-with-prefix` ·
`entries-with-prefix` · `longest-prefix` · `keys` · `values` · `entries` ·
`size` · `height` · `from-entries` · `encode` · `decode`

`TrieSet`/`TrieMap` add `within` (fuzzy) and `match` (wildcard).

Exact call-forms, arg order, and return types: `api.json` (structured) and
`docs/reference.md` (prose).

---

## Rules the agent MUST follow

1. **Rebind** the result of `add`/`set`/`delete` — tries never mutate in place.
2. **Receiver-first** argument order for the trie words: `t key value Map.set`
   (a convention so results pipe through chains and folds).
3. **Forward args have precedence**; a call resolves at the next function word
   or paren. Add parens, `end`, or `/s` (force stack) only to stop a bare
   following literal from being grabbed as an argument.
4. `keys`, `values`, `entries`, `with-prefix`, `keys-with-prefix`,
   `entries-with-prefix` are **key-sorted**.
5. `get` returns `none` and `has` returns `false` for an absent key — never an
   error. Use `has` to tell "absent" from "present with value `none`".
6. `within` / `match` exist on **`TrieSet`/`TrieMap` only**. For another
   variant, pull its `keys`/`entries` and rebuild a `TrieSet`/`TrieMap`.
7. **`decode` is strict about variants**: each namespace decodes only its own
   `encode` payloads and **raises** (catchable with `do […] error […]`) on any
   other kind. Cross-variant transfer goes through the data words
   (`keys`+`from-keys`, `entries`+`from-entries`).
8. An **empty `TstSet`/`TstMap` is `none`**, not a Map — only relevant if you
   inspect the raw trie value rather than calling namespace words.
9. To compare two key lists, use **`deq`** (structural deep equality) or
   `Assert.equal` in tests — **AQL's `eq` on lists is identity, not structural**
   (`["a"] ["a"] eq` is `false`, `["a"] ["a"] deq` is `true`).
10. A value read back through `decode` compares equal under `eq`/`deq`, but a
    decoded `none` (JSON `null` hydrated) is **not** `Assert.equal` to the
    `none` literal — assert with `eq` in that one case.

---

## Verifying your code

Build/locate `aql`, then run a scratch script or the suites:

```bash
aql path/to/your_script.aql        # run your code
aql test/smoke.aql                  # library smoke demo across all variants
for f in test/*.aql; do aql "$f"; done   # full suite (each ends "all green")
```

In this repo a SessionStart hook (`.claude/settings.json` →
`.claude/hooks/session-start.sh`) builds `aql` from the pinned commit if needed
and runs the smoke check, so a fresh session is ready to verify.

---

## Extending the library (contributors)

Read `DX-REPORT.md` for the full account; the load-bearing AQL traps are:

- **Children are computed-key Maps** (`{[k]: v}` literals, copy-returning
  `kids set (ch) child`, `StructUtil.items` enumeration — items is
  **key-sorted**, which is what makes traversal output sorted by
  construction). There is **no key-removal word**: to drop a key, rebuild the
  map from its items, skipping the key.
- **`StructUtil.items` sorts; the native map words do NOT.** Enumerate node
  children only with `StructUtil.items` (key-sorted). The native map-iteration
  words added in the `7193a7d3` window — `each`/`for-each`/`fold`/`filter`
  over a Map, plus `keys`/`vals` — walk entries in **insertion order**, and a
  node map built by repeated `kids set (ch) child` is in insertion order, not
  sorted. Swapping a sorted `StructUtil.items` fold for a native `m vals`/`m
  […] fold` therefore **silently breaks** the key-sorted guarantee (rule 4).
  It *looks* like a clean modernisation; it is a sorting bug. (`m sort`
  returns a sorted snapshot, but `m sort` + a native word is two steps where
  `StructUtil.items` is one — no win.) Verified at `5aed3834`: a `set`-built
  `{c:3,a:1,b:2}` gives `StructUtil.items` `[[a 1][b 2][c 3]]` but `keys`
  `[c a b]`.
- **Never use `StructUtil.merge` to update a node** — it is a *deep,
  index-wise* merge (`merge` is no longer a core word). Rebuild nodes with the
  explicit `mk-*` constructor; `StructUtil.setpath` is the one-field update if
  you ever need it.
- **Signature order = reverse of call order** (first parameter = top of stack).
  A namespace word whose top-of-stack type doesn't match no longer fails
  silently — the runtime raises `uncalled_function` at end of run, and
  `aql check` flags it — but still write the intended call form in a comment.
- **Reserved binding names**: `end` (call terminator), **`node`** (a
  built-in word since the Flex-container work — this library names node
  bindings `nd`), and — since the native map-iteration work (`7193a7d3`) —
  **`keys`**, **`vals`**, **`has`**, **`scan`**, and **`canon`** (this
  library renamed its `keys`-list bindings to `ks`; `val` is *not*
  reserved, only the plural `vals`). Reserved names are loud at bind time
  (`[aql/reserved_word]`), so a collision fails fast rather than silently.
  Most names that used to be rejected (`eq`, `L`, single capitals) now
  work, but avoid shadowing core words you call.
- **Index lists as `xs get (i)`**, not `xs get i` — a bare word after `get` is
  a *literal* key (JS `.key`), a parenthesised one is *computed* (JS `[expr]`).
  This is defined semantics now, not a bug.
- **Build path strings with core `add`** (`pfx ch add`); `concat`/`indexof`/
  `contains` live in `aql:string-util`, which is now **subject-last**
  (`StringUtil.contains needle haystack` forward; haystack pushed first in
  stack form).
- **`fold` binds `[element accumulator]`** (element first, accumulator on top).
- **A var-bound name does not resolve inside a nested list literal** —
  `var [[pair a] … a [np (pair get 1)] push]` fails with `undefined word`;
  bind through `def` first (`def v (pair get 1)`, then `[np v]`).
- **`filter` now takes a `[…]` quotation** like `each`/`fold` (var-destructure
  bodies included), so keep-folds are only needed when the predicate must see
  the accumulator.
- **Receiverless Reach lenses** (`$.field`, `$.0`) are inert `Reach` values
  that `each`/`filter` apply per element — `(t map-entries) each $.1` plucks
  the value column, and `radix.aql` plucks `items` pairs with `each $.1`.
- **`raise "message"`** raises a catchable error (`do […] error […]`); in the
  handler, `e "message" get` is **not a plain String** — pass it through
  `convert String` before comparing.
- **Serialise with `StructUtil.jsonify`, parse with `StructUtil.parse`.**
  String-interpolating a structure (`` `${payload}` ``) renders a contained
  `none` as `None({})`, which does not parse back; `jsonify` writes JSON
  `null`, which `parse` hydrates to `none`.
- **Chained sibling prints reverse** (`"a" print (x) print` evaluates out of
  source order — the one open forward-collection issue). One `end`-terminated
  print per statement is robust.

To add a variant: mirror an existing module's structure, export a `…Set` and a
`…Map`, add `test/<variant>_test.aql` plus `test/<variant>_prop_spec.aql` (keep
the trie-equivalence cross-check), and add the new suites to `ci/test.yml`.
