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

## Static checking (`aql check`)

`aql check` is wired into CI as an **advisory, non-gating** step (`--soft` +
`continue-on-error`), not a hard gate. This library is deliberately generic —
every node is a plain Map walked by stack-dispatched words, and the namespace
surface is exported by reference (`map-add/r`, …) — so the structural checker
can't trace those reference exports or the dynamic dispatch, and reports false
`unused_def`/`no_signature` diagnostics on code the suites prove correct. The
runnable suites are the real gate. The full per-module catalogue of what the
checker reports and why each report is a false positive lives in
[`AQL-CHECK-REPORT.md`](AQL-CHECK-REPORT.md) — project-specific evidence to
re-run on each aql bump, not template-core.

---

## Bottom line

I shipped four working, cross-checked, persistent trie variants with fuzzy
and wildcard search in AQL, so the language is clearly up to the task. The
friction was almost entirely in *discovering* the idioms, not in expressing
the algorithms — and nearly every hour lost went to a behaviour that failed
quietly instead of loudly. Louder failures and a handful of docs notes would
turn a sometimes-bewildering experience into a smooth one.
