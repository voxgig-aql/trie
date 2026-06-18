# Developer-experience report: building the trie utilities in AQL

This is a first-hand account of writing this library — four trie variants,
eight namespaces, ~2000 lines of AQL plus tests — against `aql` at commit
`b6617dd` (2026-06-01). It records what worked, what cost me time, and the
workarounds I settled on, in the hope it is useful both to the next person
writing AQL data structures and to the language authors.

> **Postscript (upgraded to `db828ec`, 2026-06-06).** Some sharp edges below
> were since fixed upstream, and the library was updated accordingly:
> #4 (`do {…}` evaluating String values as code) is fixed, so the value
> *boxing* workaround was removed; failing `Test.test` cases now surface
> loudly by name (#5-adjacent DX). Others still stand. The upgrade also
> brought breaking renames: `concat`/`indexof`/`contains` moved to
> `aql:string-util`, the test module is now `Test.*`/`Assert.*`, and `base`
> joined the reserved words — none a language *fault*, just churn to track.

> **Postscript 2 (upgraded to `958c379b`, 2026-06-11).** The language team
> verified this report item by item (their `design/VOXGIG-DX-REPORT.5.md`)
> and shipped fixes for nearly all of it — silent dispatch is now loud, maps
> take computed keys (the association-list workaround is retired from this
> library), `filter` takes quotations, `raise` and an in-memory `parse`
> exist (this library now ships `decode`), structural `deq` landed, and the
> HAMT case study's `popcount`/`insert-at`/`remove-at` asks all shipped.
> The full issue-by-issue accounting, the refactor this enabled, and the
> handful of *new* papercuts found during this upgrade are at the bottom:
> [Second upgrade review](#second-upgrade-review-958c379b-2026-06-11).

The headline: AQL is genuinely capable of expressing persistent, recursive
data structures cleanly, and once the idioms are in hand the code reads
well. Getting the idioms in hand, though, took a lot of empirical probing,
because several behaviours are surprising and fail *silently* or with an
error pointing somewhere other than the cause.

---

## What worked well

- **Recursion with pattern-matched overloads.** Trie traversal is naturally
  recursive, and AQL handles direct self-recursion and mutual recursion
  without ceremony. This is the backbone of every variant.
- **Multiple namespaces per module.** `export "A" {…}` twice in one file
  gives a clean `A.x` / `B.x` split, which let each variant ship a `…Set`
  and a `…Map` over one shared engine.
- **Persistent structures fall out naturally.** Lists and maps behave as
  values — `push` and `merge` return new structures rather than mutating —
  so immutable, path-copying tries were the path of least resistance, not a
  fight. I verified this explicitly (a `push` onto a shared list does not
  disturb other references).
- **The property-testing framework.** `test.prop` / `test.check-prop` with
  `aql:rand` generators made it easy to cross-check the four variants
  against each other over random inputs. This caught real differences.
- **Error messages often point at the fix.** The recurring hint *"forward
  args for X may have run into the next word; group the call with parens"*
  is genuinely good and was usually correct.

---

## Sharp edges (and the workarounds)

These are ordered roughly by how much time each one cost me.

### 1. Argument order is the reverse of the call, and a type mismatch fails *silently*

The rule "the first signature parameter is the top of the stack" means a
function's parameter list is the **reverse** of its left-to-right call
order. Calling `t key val Xxx.set` requires the signature
`[val:Any key:String t:Map]`, not `[t key val]`. I inverted this more times
than I'd like to admit.

What made it costly is the *failure mode for namespace words*: when the
top-of-stack type doesn't match the first parameter, dispatch does not
error — it leaves the function value on the stack as data. So a wrong-order
`TrieMap.get` call silently produced output like `fn map-get(Map, String)`
interpolated into a string, with no diagnostic. For a plain (non-namespace)
word the mismatch *does* error, which is the more helpful behaviour.

*Workaround:* I adopted one mnemonic — **signature = reverse of call
order** — and wrote the intended call form in a comment above every
function. A linter rule that flagged a namespace member resolving to a bare
function value (almost always an arity/order bug) would have saved hours.

### 2. `fold` binds `[element accumulator]`, not `[accumulator element]`

The fold body receives the *element* first and the *accumulator* second
(`var [[elem acc] …]`), with the accumulator on top of the stack. I
initially guessed the opposite, which silently produced wrong results for
list-building folds (the accumulator and element got swapped into `push`).
Worth stating prominently in the docs with a list-building example, since
reduce/fold conventions vary across languages.

### 3. `merge` is a deep, index-wise merge

`{kids: [99]} {kids: [10, 20]} merge` yields `{kids: [99, 20]}` — the lists
are merged element-by-element, not replaced. I reached for `merge` to
update one field of a node and it silently fused sibling child-lists
together, producing a tree where one branch's nodes leaked into another.
This was the single hardest bug to localize because the corruption appeared
in a subtree the edit never touched.

*Workaround:* never `merge` to update a field. Rebuild the whole node with
an explicit constructor (`do {a: [..], b: [..]}`). A shallow `assoc`/`with`
word that replaces a single key without deep-merging would remove a real
foot-gun.

### 4. `do {k: [v]}` evaluates the map's values *as code*

The idiomatic constructor `do {field: [expr]}` evaluates each value
quotation — and if the result is a String that happens to name a word
(`"do"`, `"if"`, `"get"`, `"fold"`), that word is *dispatched* instead of
stored. So a `…Map` storing the value `"if"` corrupted its node. Plain
non-word strings (`"hello"`) were fine, which is exactly what makes this
dangerous: it passes every casual test and breaks on real data.

*Workaround:* store values **boxed** — wrapped in a one-element list,
`[] val push` — which is inert under `do`, and unbox on the way out. Every
variant does this. (Bare-word map values like `{a: v}` resolve a
*top-level* `def` but **not** a function parameter — "undefined word" — so
that escape hatch wasn't available inside functions.)

### 5. `eq` on lists is identity, not structure

`["a" "b"] ["a" "b"] eq` is `false`. `assert.equal` *does* compare lists
deeply (so unit tests were fine), but a property body using `eq` to compare
two key-lists silently compared identities and passed vacuously — my
cross-variant equivalence checks were, for a while, only verifying that the
*lengths* matched. A distinct word for structural equality (or making `eq`
structural for value types) would help; at minimum the asymmetry with
`assert.equal` deserves a docs note.

### 6. `get` with a bare variable index returns `none`

`xs get 1` works; `xs get i` (where `i` is a binding) returns `none` — the
forward `get` grabs the bare word rather than its value. `xs get (i)`
(parenthesized) works. This is the same forward-collection issue as #1 but
manifests as a silent `none` rather than an error, and it bit me twice
(once in real code, once in a test helper that then passed vacuously).

### 7. Reserved words can't be binding names — and the set is wider than expected

Several names cannot be used as `def`/parameter/`var` bindings:
- `end` (the call terminator),
- `node` (a builtin word),
- `eq` (the comparison word) — this one cost time, because using it as a
  field/param name silently dispatched the comparison and produced an
  infinite loop in a ternary-search-tree constructor,
- single uppercase letters (`L`, `P`) — they collide with type names.

The map *key* `"end"` (a string) is fine; only the binding is not. The
error when it does surface (`invalid_word_name`, or a downstream signature
error) rarely names the real problem. A short "reserved identifiers" list
in the reference would help a lot.

### 8. String interpolation is fragile as an argument to a recursive call

`` `${a}${b}` `` works at the top level of an expression, but using it
*inline* as an argument to a forward-dispatched recursive call (or binding
it where the result is a word-like string) produced "no matching signature"
and "undefined word" errors that pointed at the call, not the template.

*Workaround:* build path strings with `concat` (`[a b] concat`) and bind
them to a simple variable before passing them on. Robust everywhere I tried
it.

### 9. Smaller papercuts

- **No way to build a map with computed keys.** `set` works only on
  `Store`/`Object`, not on a `Map` literal; `make Map …` is unsupported;
  and `refine Object` dynamic fields can't be enumerated (`items` returns
  only declared fields). The net effect: a dynamically-keyed, *walkable*
  map isn't expressible, which is why every node here stores children as an
  **association list** `[[key, child], …]` instead of a keyed map.
- **`filter` wants a `Function`, not a `[…]` quotation**, unlike `each`
  /`fold` which happily take a bracket body. I used `fold` everywhere
  instead.
- **Forward arguments have precedence — by design (I misjudged this).** A word
  collects the tokens *after* it as arguments, stopping at the next function
  word or a closing paren, and otherwise falls back to the stack. So a
  terminator is rarely needed: `(… my-fn)`, `… my-fn next-word`, and
  `import "x"` all resolve on their own. The only case that needs
  disambiguation is when a bare, type-compatible **literal** immediately
  follows a stack-form call — then use parens, `end`, or the **`/s`** modifier,
  which pins the call to stack args (`5 5 cmp/s 9` → compares `5` and `5`,
  leaves `9`; `5 5 cmp 9` → forward-grabs `9`). My first draft of this report
  overstated it as "every call needs `end`"; it does not — that was my error,
  not a language wart.
- **`if` is safe all-forward.** I kept every `if cond [then] [else]` with
  the condition and branches all forward of the word; the mixed form is the
  one to avoid.
- **Print order is reversed** (the first printed line appears last), so demo
  scripts print a leading blank line to restore source order.
- **No custom error raising.** `error` is a *handler* combinator
  (`do […] error […]`); there's no `raise`/`throw` with a message. Not
  needed here (tries don't raise), but worth knowing.
- **No in-memory jsonic parser.** `read` is file I/O; there is no
  string→value parse exposed. That's why this library's round-trip is
  data-based (`from-keys`/`from-entries`) rather than a string `decode` of
  the `encode` snapshot. A `parse`/`unjson` word would close the loop.
- **`do {k:[v]}` generators can be order/charset-sensitive.** A two-field
  `do {keys:[…], q:[…]}` property generator that referenced a `def`-bound
  charset failed where the same structure with a literal charset worked. I
  sidestepped it by generating a single value per property.

---

## Case study: what would it take to make a HAMT worthwhile?

When the brief asked for four variants, I implemented a **burst trie** for
the fourth and explicitly declined a **HAMT** (hash array-mapped trie). It
is worth recording *why*, because the answer is more nuanced than "AQL
can't do it" and it points at a few concrete language gaps. (The facts
below were confirmed against the source and quick probes at `b6617dd`; I
did not build a HAMT end to end, so the "only blocker" claim in Level A is
a strong inference, not an executed result.)

A HAMT keeps each node's present children in a small **packed array** and
uses a per-node integer **bitmap** to say which of (say) 32 slots are
occupied; the slot's position in the packed array is
`popcount(bitmap & (bit − 1))`. Its whole reason to exist — over a
balanced tree, a sorted trie, or a plain hash map — is *performance from
memory layout*: a contiguous, O(1)-indexed array that is cheap to copy
(≤32 slots) for persistence or mutate in place for bulk builds.

Crucially, a HAMT indexes children by an integer **slot**, not by a
dynamic string key. So it sidesteps the limitation that shaped every other
variant here (AQL can't build maps with computed keys, and `refine Object`
fields aren't enumerable) — integer-indexed `List`s cover it. That makes
the HAMT *more* expressible in AQL than I first assumed. The question
splits cleanly into two levels.

### Level A — to express a *correct, persistent* HAMT

Already present and sufficient: the full bitwise suite (`band` `bor`
`bxor` `bnot` `bsl` `bsr` `busr`), integers wide enough to mask, hashing to
a fixed-width integer (`bin.fnv32` / `bin.fnv64`), O(1) list indexing
(`get`), and structural sharing via copy-returning ops. Bit-slicing a hash
(`(h bsr 5) band 31`) works directly.

Missing or awkward, but minor:

1. **`popcount`** — the one genuinely absent primitive, and the core of the
   slot-indexing trick. It is implementable in user code (a SWAR sequence
   with the existing bitwise/multiply words, or a ≤64-step loop), so it is
   a convenience rather than a blocker — but a native `popcount` is the
   single highest-leverage addition.
2. **`insert-at` / `remove-at` for lists** — to grow or shrink the packed
   child array by one slot. Today you compose `take`/`concat`/`shed`; a
   primitive is cleaner and avoids the O(n) rebuild.
3. **Defined fixed-width *unsigned* integer semantics** (a `u32`/`u64`, or
   documented shift/wrap behaviour). The bitmap depends on well-defined
   shifts and no sign surprises at bit 31/63. Manual masking works but is a
   foot-gun.

With just `popcount` (or its in-language equivalent) a correct persistent
HAMT is writable today.

### Level B — to make a HAMT actually *pay off*

This is the real answer, and none of it is surface syntax. An interpreted,
GC'd, value-semantics language cannot deliver a HAMT's performance
advantage without:

1. **Mutable, fixed-width, unboxed arrays** with an in-place O(1)
   `set`/`insert` contract. AQL has indexed `set` *only* on the separate
   `Array` type, not on plain `List`s (`[10 20 30]` is a `List` and `set`
   rejects it), and the mutation-vs-copy contract isn't exposed. This is
   what enables the *transient* fast path (à la Clojure) that makes bulk
   construction competitive.
2. **Layout guarantees** — contiguous packed storage and unboxed small ints
   for the bitmap — for the cache locality that *is* the HAMT's edge over
   other trees. Boxed values defeat this entirely.
3. Realistically, **a native persistent-map type in the runtime**
   (HAMT/CHAMP-backed), the way Clojure, Scala, and Erlang ship one. Then
   `make`/`get`/`set`/`merge` over a large map become O(log₃₂ n) with
   structural sharing and user code never touches a bitmap — and, as a
   bonus, this would also retire AQL's dynamic-key-map limitation.

### Takeaway

For *expressiveness*, add `popcount` (ideally also `insert-at`/`remove-at`
and unsigned-int clarity) and a HAMT becomes a reasonable pure-AQL
exercise. For *HAMT-class performance*, that is a runtime decision: ship a
native persistent map, and/or add mutable unboxed fixed-width arrays with
transients. The burst trie was the pragmatic stand-in precisely because it
trades the bitmap-packing trick for flat buckets — and buckets are just
`List`s, which AQL represents naturally.


## Suggestions, in priority order

1. **Surface silent dispatch failures.** The two costliest bugs (#1, #6)
   both failed silently — a namespace word left undispatched, a `get`
   returning `none`. A warning when a namespace member resolves to a bare
   function value, and an error (not `none`) when `get` is handed a bare
   undefined word, would catch a whole class of mistakes.
2. **A shallow field-update word** (`with`/`assoc`) so `merge` (#3) isn't
   the only option for "replace one key".
3. **Document the gotchas:** argument-order = reverse-of-call, fold binding
   order, `merge` depth, `do`-evaluates-values, list `eq` vs `assert.equal`,
   reserved identifiers, and `get (i)` vs `get i`. Each is a one-line note
   that would save a newcomer an afternoon.
4. **A jsonic string parser** to complement `jsonify`, enabling true
   `encode`/`decode` round-trips.

---

## Bottom line

I shipped four working, cross-checked, persistent trie variants with fuzzy
and wildcard search in AQL, so the language is clearly up to the task. The
friction was almost entirely in *discovering* the idioms, not in expressing
the algorithms — and nearly every hour lost went to a behaviour that failed
quietly instead of loudly. Louder failures and a handful of docs notes would
turn a sometimes-bewildering experience into a smooth one.

---

## Second upgrade review (`958c379b`, 2026-06-11)

This library was re-verified and refactored against `aql` `958c379b` —
110 commits past the previous `db828ec` pin. The language team had
re-verified this report item by item against their `main` (see
`design/VOXGIG-DX-REPORT.5.md` and `design/VOXGIG-AQL-REPORTS.5.md` in the
aql repo) and shipped a remarkable amount of it. Everything below was then
confirmed first-hand while upgrading: every status is backed by this repo's
suites running green at the new pin, or by a minimal probe.

### The original sharp edges, re-scored

| # | Issue (2026-06-01) | Status at `958c379b` | Done here |
|---|---|---|---|
| 1 | Namespace dispatch type-miss fails **silently** | ✅ **fixed** — the runtime raises `[aql/uncalled_function]` at the end-of-run drain with the call-site span; `aql check` also flags `uncalled_function` and a `forward_strands_operand` advisory | nothing to change — the costliest trap in this report is gone |
| 2 | `fold` binds `[element accumulator]` | 📖 documented upstream (`describe fold` + REFERENCE callout); behaviour unchanged | fold bodies untouched |
| 3 | `merge` is a deep, index-wise merge | 🟠 still deep *by design*, but `merge` **left core** (now `StructUtil.merge`) and `StructUtil.setpath` is the copy-returning one-field update | nodes still rebuilt with `mk-*` constructors |
| 4 | `do {…}` evaluated map values as code | ✅ stayed fixed | — |
| 5 | `eq` on lists is identity | 📖 by design, documented — and structural **`deq`** landed | the prop suites' hand-rolled `list-eq` helper is deleted; cross-variant checks use `deq` |
| 6 | `xs get i` returns `none` | 📖 redefined as intentional JS-like semantics: bare word = literal key (`.key`), parenthesised = computed (`[expr]`); documented | code already used `get (i)` |
| 7 | Reserved binding names (`node`, `eq`, `L`, …) | 🟠 **mostly relaxed** (`eq`, `L`, single capitals now bind fine) — but **`node` became reserved again** as a built-in word of the new Flex-container work, which broke every module in this library at call time | all node bindings renamed to `nd` |
| 8 | Interpolation fragile in recursive calls | ✅ fixed — recursive `` `${…}` `` expands correctly | kept (collectors still interpolate paths) |

### The papercuts (#9), re-scored

- **Maps with computed keys** — ✅ **fixed, and it reshaped this library.**
  `{[k]: v}` literals evaluate the key; `set` on a Map is **copy-returning**
  (`{a:1} set (k) 2` leaves the receiver untouched — verified); and
  `StructUtil.items` enumerates entries as **key-sorted** `[k v]` pairs
  regardless of insertion order. The association-list workaround is retired:
  the standard trie's children, the radix tree's edges (keyed by first
  character — the radix invariant makes that unique), and the burst trie's
  spine are all real maps now. A free consequence of sorted enumeration:
  every traversal emits keys in lexicographic order *by construction*, so the
  listing words dropped their trailing `sort`s, and `entries` is collected in
  one walk instead of a keys-walk plus per-key lookups. Residuals: there is
  **no key-removal word** (delete still rebuilds the children from `items`,
  same O(n) as the old list splice), and each `set` copies the map — the
  native persistent map (HAMT Level B below) remains the perf answer.
- **`filter` wants a `Function`** — ✅ fixed: `filter` takes a `[…]` quotation
  (var-destructure bodies included). Adopted for the burst bucket scans.
  Keep-folds remain only where the predicate needs the accumulator.
- **Forward-arg edges / print order** — top-level print order now matches
  source order, and `import` without `end` is fine again under the lazy
  structure-first resolution engine. The one survivor: **chained sibling
  prints still reverse** (`"a" print (x) print`), so the smoke demo keeps one
  `end`-terminated print per statement.
- **No custom error raising** — ✅ fixed: `raise "message"` raises a
  catchable error (`do […] error […]`). Adopted: `decode` raises on a
  wrong-kind payload. *New papercut:* in the handler, `e "message" get`
  **prints** like the message but is not a plain `String` — it has `size` 0
  and is not `eq` to the equal-looking literal; pass it through
  `convert String` before comparing.
- **No in-memory jsonic parser** — ✅ fixed: `StructUtil.parse` decodes
  jsonic/JSON text (loud `parse_error` on garbage), `Vm.parse` parses AQL
  source. Adopted: every namespace now ships **`decode`**, the true inverse
  of `encode`, closing the round-trip this report asked for. Two *new
  papercuts* found wiring it up:
  1. String-interpolating a payload (`` `${payload}` ``) is **not** a
     serialiser: a contained `none` renders as `None({})`, which `parse`
     does not read back. `StructUtil.jsonify` is the matched pair (`none` →
     JSON `null`), so `encode` switched from interpolation to `jsonify`.
  2. `parse` hydrates JSON `null` to a none that is `eq`/`deq`-equal to the
     `none` literal but **`Assert.equal` still distinguishes them**
     (`expected None, got none`). Tests assert that one case via `eq`.
- **Generator order/charset sensitivity** — not retested (the single-value
  generators kept working); unchanged note.

### HAMT case study, revisited

Level A is now unblocked exactly as the case study asked: **`popcount`
landed** (`BinUtil.popcount`, alongside `clz`/`ctz`/`bitlen`/`mask`/…) and
**`insert-at`/`remove-at` landed** (`ArrayUtil`, copy-returning, loud on
out-of-range). A correct persistent HAMT is now a reasonable pure-AQL
exercise — it would slot in as a fifth variant behind the same `…Set`/`…Map`
surface (hash the key, bit-slice with `bsr`/`band`, index the packed child
list by `popcount(bitmap & (bit-1))`). What this library does *not* get from
it today is the payoff: Level B (mutable unboxed fixed-width arrays /
layout guarantees / a native persistent map) is unchanged, so a pure-AQL
HAMT would be a demonstration, not a speedup. The new `FlexMap`/`FlexList`
mutable Node containers and constructible `make Array` inch toward the
transient story, but the layout guarantees that make a HAMT *fast* are
still a runtime decision. Unchanged conclusion: worth doing when a native
persistent map ships, or as an expressiveness showcase.

### Breaking changes hit during this upgrade

None of these are language *faults*; all are churn a downstream consumer
should expect to track on an unpinned `main`:

| Change | Effect here |
|---|---|
| `node` is a reserved built-in word | every module failed at call time (`[aql/reserved_word]`); bindings renamed to `nd` |
| `aql:string-util` went **subject-last** | the pbt suite's stack-form `StringUtil.contains` silently flipped to needle-vs-needle; call rewritten (haystack pushed first) |
| `merge` moved out of core into `aql:struct-util` | no effect (this library never merges nodes — see #3) |
| `refine Object` removed (class/object split) | no effect (never used here) |
| Digit-led stack words renamed (`2dup` → `dup2`, …) | no effect (never used here) |
| Map/structure print form changed (jsonic single-quote style) | the pbt `encode`-shape property updated along with the `jsonify` switch |

### Suggestions from the original report, all four accounted for

1. **Surface silent dispatch failures** — ✅ shipped (runtime
   `uncalled_function` + three new `aql check` diagnostics).
2. **A shallow field-update word** — ✅ resolved as `StructUtil.setpath`
   (an `assoc`/`with` alias was explicitly rejected as duplication — fine).
3. **Document the gotchas** — ✅ landed as a docs batch (fold order, merge
   depth, `eq` vs `deq`, literal-vs-computed `get` keys, ADR-004
   forward-by-default, upgrade notes).
4. **A jsonic string parser** — ✅ shipped (`StructUtil.parse`).

That is a 100% hit rate on the priority list, plus the HAMT asks. The two
silent-failure mechanisms that dominated the original report are both loud
now; what remains open upstream is minor (chained-print ordering) or
explicitly deferred runtime work (native persistent map). The new
papercuts found this round — `node` re-reserved, the not-a-String error
message, interpolation-vs-jsonify for `none`, hydrated-null vs
`Assert.equal` — are exactly the kind of small, silent asymmetries this
report exists to flag, and none cost more than minutes against a pinned,
tested upgrade.

## Third upgrade review (`7193a7d3`, 2026-06-18)

Re-verified and migrated against `aql` `7193a7d3` — 39 commits past
`958c379b`. The headline of this window is the **native map-iteration
work** (`each`/`for-each`/`fold`/`filter` gained Map overloads, the
`KeyVal` entry type landed, and `keys`/`vals` became core words), plus a
batch of DX fixes the language team shipped in response to a *different*
consumer's report (`voxgig-aql/decision/dx-report.md`) — several of which
also close papercuts this library logged in round 2. Every status below is
backed by this repo's ten suites running green at the new pin, or a
minimal probe.

### The one breaking change here

| Change | Effect here |
|---|---|
| `keys` and `vals` became reserved core words (native map columns); `has`, `scan`, `canon` also now reserved | only **`keys`** collided — it was this library's binding name for a key list in `build-from-keys`/`set-from-keys` and the variant equivalents (plus `[[keys …]]` destructures in the property suites). Renamed every such *binding* to **`ks`**; the public API names (`TrieSet.keys`, the `keys:` field in `encode` payloads) are map keys, not bindings, and are untouched. Same churn class as round 2's `node`→`nd`, and just as loud (`[aql/reserved_word]` at bind time). `val` is **not** reserved — only the plural `vals` — so the pervasive `val` field/binding survived. |

That was the *entire* migration: no behavioural change, no logic touched,
suites green after a mechanical rename. The native `keys`/`vals`/map-`fold`
words are an **adoption opportunity** (they would retire the
`StructUtil.items`-fold idiom the same way round 2 retired association
lists), but that is a refactor, not a fix — deferred, not required.

### Round-2 papercuts, re-scored

| Papercut (round 2) | Status at `7193a7d3` |
|---|---|
| `e "message" get` is **not a String** (size 0, not `eq` to the literal) | ✅ **fixed** — it is now a genuine `String` (`eq` to the literal, correct `size`), part of the do/error stack-neutrality work. The `convert String` guard in this library's `decode` tests is now a harmless no-op, kept for back-compat. |
| Interpolating a payload renders `none` as `None({})`, unreadable by `parse` | 📖 unchanged **by design** — `StructUtil.jsonify` remains the matched serialiser (`none` → JSON `null`); `encode` already uses it. |
| A `parse`-hydrated `null` is `eq`/`deq`-equal to `none` but `Assert.equal` distinguishes it | 🟠 **persists** — re-probed: `eq`/`deq` both `true`, yet `Assert.equal none hydrated` still raises `expected None, got none` (the value now renders lowercase, from `2a632eef`, but the assert-vs-eq asymmetry stands). Tests still assert that one case via `eq`. |
| Chained sibling prints reverse (`"a" print (x) print`) | 🟠 **persists** — the two-phase forward-collection model was *documented* (`design/FORWARD-COLLECTION-PHASES.10.md`) but the reversal is unchanged; the smoke demo keeps one `end`-terminated print per statement. |
| `node` re-reserved | 🟠 still reserved, now with company (`keys`/`vals`/`has`/`scan`/`canon`). |

### DX improvements that landed this window

- **`do`/`error` is stack-neutral.** The error branch now leaves *exactly*
  the handler's result — any residue the `do` block pushed before raising
  (or the caught error itself, if the handler ignores it) is stripped,
  mirroring the success pass-through. Verified. Directly relevant to
  `decode`'s `do […] error […]` guard.
- **Errors carry location across an import boundary.** An error raised
  inside an imported `fn` now renders with the *module* file's name, line,
  and caret (`--> /path/mod.aql:row:col`) instead of losing its position —
  exactly the fidelity entry-file errors already had. This matters because
  the whole library is consumed via `import`; a downstream `decode` raise
  now points into `trie.aql`, not nowhere.
- **Swapped-argument hint.** When a dispatch fails but the argument tuple
  matches a signature under a permutation, the error now says "one exists
  for (String, Map) — did you swap the arguments?" instead of the
  misleading forward-grouping hint. Complements the round-2
  `uncalled_function` work as the second half of the "loud dispatch
  failure" story.
- **Core `has` word.** A total presence predicate (`Boolean`, `false` on
  missing key / out-of-range / `none` parent) across Map/List/record/Array
  — the general form of this library's namespace `has`, and the clean way
  to distinguish absent from present-with-`none` (rule 5) in any consumer
  code that touches raw nodes.
- **Flex writes ADOPT.** A plain Map/List stored into a flex container is
  now deep-copied to flex (so a later write through it sticks — the old
  "mixed tree" silently-lost-write bug, `e2abf68d`); a flex value stored
  into a flex container is *shared* by reference; a value stored into a
  plain container is snapshotted immutable. Verified all three. This makes
  the flex-transient build pattern robust without hand-`flex`-ing every
  child — strengthening the "FlexMap is the transient twin" half of the
  persistent-map discussion below.
- **`canon` word** — round-trippable canonical AQL source for any value
  (`{end:false kids:{a:1} val:none}`). An alternative to this library's
  JSON-targeted `encode`; not adopted (we want portable JSON text), but a
  clean inspection/snapshot tool.
- **`aql check` gained positions.** Diagnostics now carry `row:col` and an
  explicit `[info]`/`[warning]`/`[error]` severity (the round-2 re-run
  complained of position-less reports). The false-positive *classes* and
  *volume* are unchanged, so the advisory-only verdict stands — see the
  check report's round-3 note.

### The standing asks (from the persistent-map design review)

A separate design thread this round stress-tested whether the runtime's
mutable containers close the long-standing "every Map `set` is a full
copy" ceiling. They do not — but they sharpened the ask:

1. **A native persistent Map** (CHAMP/HAMT behind the *existing*
   copy-returning `set` — a representation swap, not a new type or
   semantics) remains the headline performance ask. Map's contract is
   already persistence-shaped; only the cost model is wrong (O(n) copy per
   `set`, which makes the idiomatic `fold`-build O(n²) — measured 4.4 s for
   4 000 entries vs 0.47 s for the in-place flex equivalent). Keys are
   string-only and every surface enumeration (`print`, `jsonify`,
   `StructUtil.items`) is already key-sorted, so hash order would stay
   unobservable — the swap is invisible to every existing program.
2. **An `inflex` / O(1) seal** is the cheap companion ask: today `node`
   (the flex→immutable freeze) is a deep copy, so a userland persistent
   structure built on flex transients pays an O(size) seal at the API
   boundary, erasing the win. An ownership-transfer seal (Clojure's
   `persistent!`: flip an edit bit, invalidate stale writers) plus a
   transitively-contains-flex purity bit would make the seal O(1) and
   legitimise userland persistent structures — smaller than shipping CHAMP,
   and exactly the word a CHAMP-with-transients API would want anyway. The
   flex-adopt work above is adjacent but does not provide it.

Neither blocks this library — tries are narrow-fanout, so copy-returning
`set` copies little, and the data words (`from-keys`/`from-entries`) batch
the build. They are upstream wishes, logged here because this is the report
the language team reads.
