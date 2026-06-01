# Explanation

Understanding-oriented discussion of how these trie utilities work and why
they are built this way. Read this for the *why*; for the *what*, see the
[Reference](reference.md); for *how to get a job done*, the
[How-to guides](how-to.md).

---

## What a trie is for

A trie (prefix tree) stores a set of strings — or a map from strings to
values — arranged so that keys sharing a prefix share a path through the
structure. That single property makes a family of operations cheap and
natural:

- **membership** — exact, with no false positives or negatives;
- **prefix enumeration** — "every key starting with `ca`", the engine
  behind autocomplete;
- **longest-prefix matching** — "the longest stored key that begins this
  string", the engine behind routing tables and tokenizers;
- **sorted iteration** — keys come out in order for free.

A trie is the right tool when prefixes matter. When they don't — when you
only need set membership and want to spend the least possible memory — a
hash set or a [bloom filter](https://github.com/aql-lang) is a better fit.

---

## How membership and prefixes work

Every variant walks the key one piece at a time from the root, following
the edge labelled by the current piece. A node carries an `end` flag that
marks whether a key terminates there:

```
add "cat"          → path  c · a · t , mark end at the last node
has "cat"          → walk  c · a · t , is end set?            → yes
has "ca"           → walk  c · a     , is end set?            → no
with-prefix "ca"   → walk  c · a     , collect all keys below → [car, card, cat]
```

`with-prefix` is just "navigate to the prefix, then list everything
beneath." `longest-prefix` is "walk the query, remembering the deepest
node whose `end` is set." Because the walk visits children in sorted
order, every list the library returns is sorted.

There is no probabilistic element here: unlike a bloom filter, a trie
stores the keys, so `has` is always exact.

---

## The four variants

All four answer the same questions identically — the property suite
cross-checks each against the standard trie over random key sets. They
differ only in how a node's children are arranged, which changes memory
use and the shape (and depth) of the tree.

### Standard trie (`trie.aql`)

One node per character. A node's children are an association list of
`[char, child]` pairs. Simple and predictable; the baseline. Its weakness
is long, unshared keys: storing `"internationalization"` spends one node
per letter even though none of those letters branch.

### Radix / PATRICIA tree (`radix.aql`)

Collapses every chain of single-child nodes into one edge carrying a
multi-character *label*. `"romane"` and `"romanus"` share a single
`"roman"` edge that then forks. Inserting a key that diverges inside a
label **splits** the edge; deleting a key that leaves a node with one
child **merges** them back. The payoff is far fewer nodes for sparse key
sets; the cost is the split/merge bookkeeping.

### Ternary search tree (`tst.aql`)

Each node holds a single character and three children: `lo` and `hi` form
an ordinary binary search tree over the *alternatives* at one position,
and `mid` advances to the *next* character when this one matches. This
needs only three pointers per node regardless of alphabet size, so it
scales to large or Unicode alphabets where a per-node child map would be
wasteful. An in-order walk (lo, then this character's subtree, then hi)
yields sorted keys. The trade-off is a deeper descent — you may pass
through several `lo`/`hi` nodes before advancing one character.

### Burst trie (`burst.aql`)

Keeps keys in flat **buckets** (small association lists of suffix →
value) until a bucket exceeds the burst limit, at which point it
**bursts** into a trie node whose children are fresh sub-buckets keyed by
the next character. The trie spine stays shallow while most keys live in
buckets that are cheap to scan — the idea behind the cache-conscious
HAT-trie. (A true bitmap/array-mapped trie wants fixed-width bit vectors,
which AQL's data model does not offer; the burst trie is the member of
that family that maps cleanly onto lists and maps.)

### Picking one

Start with the standard trie. Move to radix when keys are long and
sparse, to a TST when the alphabet is large, to a burst trie when you want
flat buckets over a shallow spine. Because the API is identical, the
decision is reversible with a one-line change.

---

## Design choices specific to this library

### Persistence (immutability)

`add`, `set`, and `delete` return a *new* trie and never mutate the input.
Each rebuilds only the nodes along the edited path; untouched subtrees are
shared by reference. This makes tries safe to keep old versions of, pass
around, and reason about, and it fits AQL's value-oriented data model —
maps and lists behave as values, so "mutate in place" is not the natural
idiom here.

### Children as association lists

A node's children are stored as a list of `[label, child]` pairs rather
than as a map keyed by the character. This is deliberate: AQL maps cannot
be constructed with computed keys, and `refine Object` instances cannot be
enumerated, so neither can hold a dynamic, walkable set of children. A
list of pairs is the one shape that is both rebuildable and iterable. The
cost is that finding a child is a linear scan of the siblings — fine for a
modest branching factor, and exactly what the ternary search tree
optimizes away by ordering siblings into a BST.

### Boxed values

Stored values are wrapped in a one-element list (a "box") inside each
node. The node constructor builds its map with AQL's `do {…}` form, which
*evaluates* the map's values — so a bare String value equal to a word name
(`"if"`, `"do"`, `"get"`) would be dispatched as code instead of stored.
Boxing keeps the value as inert list data; the library unboxes it on the
way out. This is invisible to callers but is why a `…Map` can safely store
*any* value.

### Why not `merge`

Nodes are rebuilt with an explicit field-by-field constructor, never with
AQL's `merge`. `merge` is a deep, index-wise merge: merging a replacement
`kids` list into a node would fuse it element-by-element with the old
list, silently entangling sibling subtrees. The explicit constructor
replaces a field outright, which is what rebuilding a path requires.

### `height` is per-variant

`size` (the number of keys) is comparable across variants, but `height`
reflects each structure's own shape — node-depth for the standard trie,
fewer levels for a radix tree over the same keys, a deeper count for a
ternary search tree, and bucket-vs-spine for a burst trie. Treat `height`
as a window into the chosen structure, not a cross-variant metric.

---

## Further reading

- [Tutorial](tutorial.md) — build your first trie step by step.
- [How-to guides](how-to.md) — task-focused recipes, including choosing a
  variant.
- [Reference](reference.md) — the exact API.
