# Tutorial: your first trie

This is a hands-on lesson. By the end you will have built a small boru
script that stores a dictionary of words, autocompletes a prefix, and
looks up a value — the core of what a trie is good for. You need no prior
knowledge of tries, just a working `boru` binary (see
[How-to → Install and run](how-to.md#install-and-run-aql)) and this
repository checked out.

Type the script into a file as we grow it, and run it after each step.

> **AI agents:** for the calling convention and a verified cheat-sheet,
> see [AGENTS.md](../AGENTS.md).

---

## Step 1 — import a variant and make a set

We will start with the standard trie used as a **set** of words. Create a
file `words.aql` next to `trie.aql`:

```boru
import "./trie.aql"

# boru prints a program's first line last; one blank line up front keeps
# the rest of the output in source order.
"" print

def t0 (TrieSet.make)
def t1 (t0 "cat"  TrieSet.add)
def t2 (t1 "car"  TrieSet.add)
def t3 (t2 "card" TrieSet.add)
def t4 (t3 "dog"  TrieSet.add)

`words: ${(t4 TrieSet.keys)}` print
```

Run it:

```console
$ boru words.aql
words: ['car' 'card' 'cat' 'dog']
```

Two things to notice. Each `add` returns a *new* trie — the trie is
**immutable**, so we thread the result through `t1`, `t2`, … rather than
mutating in place. And `keys` comes back **sorted**, for free, because a
trie stores keys in order.

---

## Step 2 — ask what it contains

`TrieSet.has` answers membership exactly — no false positives:

```boru
`cat?  ${(t4 "cat" TrieSet.has)}` print
`ca?   ${(t4 "ca"  TrieSet.has)}` print
`emu?  ${(t4 "emu" TrieSet.has)}` print
```

```console
cat?  true
ca?   false
emu?  false
```

`cat` was added, so it reads `true`. `ca` reads `false` even though it is a
prefix of `cat` and `car` — a *prefix* is not a *member* unless you added
it. `emu` was never added, so `false`.

---

## Step 3 — autocomplete a prefix

This is the move tries are made for. `with-prefix` returns every key that
starts with what the user has typed so far:

```boru
`complete "ca": ${(t4 "ca"  TrieSet.with-prefix)}` print
`complete "d":  ${(t4 "d"   TrieSet.with-prefix)}` print
`complete "z":  ${(t4 "z"   TrieSet.with-prefix)}` print
```

```console
complete "ca": ['car' 'card' 'cat']
complete "d":  ['dog']
complete "z":  []
```

`"ca"` offers the three words beneath it; `"z"` matches nothing and yields
an empty list. That is a working autocomplete in one call.

---

## Step 4 — longest-prefix matching

Sometimes you have a long string and want the longest stored key that
*starts* it — the heart of routing tables and tokenizers. Add the word
`"car"` is already there; ask what prefixes `"cartoon"`:

```boru
`longest of "cartoon": ${(t4 "cartoon" TrieSet.longest-prefix)}` print
`longest of "cat":     ${(t4 "cat"     TrieSet.longest-prefix)}` print
`longest of "emu":     ${(t4 "emu"     TrieSet.longest-prefix)}` print
```

```console
longest of "cartoon": car
longest of "cat":     cat
longest of "emu":     None
```

`"car"` is the longest member that begins `"cartoon"` (`"card"` does not,
it diverges at the 4th letter). `"cat"` is itself a member, so it is its
own longest prefix. Nothing prefixes `"emu"`, so `none`.

---

## Step 5 — store values, not just keys

Swap the set for a **map** when each key should carry a value. The only
changes: use `TrieMap`, and `set` takes a value. Let us map each word to
its length. Create `lengths.aql`:

```boru
import "./trie.aql"
"" print

def m0 (TrieMap.make)
def m1 (m0 "cat"  3 TrieMap.set)
def m2 (m1 "card" 4 TrieMap.set)

`get cat:     ${(m2 "cat"  TrieMap.get)}` print
`get card:    ${(m2 "card" TrieMap.get)}` print
`get missing: ${(m2 "emu"  TrieMap.get)}` print
`entries:     ${(m2 TrieMap.entries)}` print
```

```console
get cat:     3
get card:    4
get missing: None
entries:     [['card' 4] ['cat' 3]]
```

`get` returns the bound value, or `none` for an absent key. Like `keys`,
`entries` comes back sorted by key. Everything you
learned about prefixes still applies — a `TrieMap` has
`keys-with-prefix` and `longest-prefix` too.

---

## Step 6 — try another variant (same code)

The four variants share one API, so switching is a one-line change. Take
the set script and swap the import and the namespace prefix for the radix
tree:

```boru
import "./radix.aql"       # was ./trie.aql
"" print
def t ((((( RadixSet.make) "cat" RadixSet.add) "car" RadixSet.add) "card" RadixSet.add) "dog" RadixSet.add)
`complete "ca": ${(t "ca" RadixSet.with-prefix)}` print
```

```console
complete "ca": ['car' 'card' 'cat']
```

Identical answer. The radix tree stores the same words more compactly
(merging shared chains into single edges), but you cannot tell from the
outside — which is the point. The same swap works for `TstSet`/`TstMap`
and `BurstSet`/`BurstMap`.

---

## What you've learned

- `make`, then thread `add`/`set` results — tries are immutable.
- `has` is exact; a prefix is not a member unless added.
- `with-prefix` is autocomplete; `longest-prefix` is longest-match.
- `keys` (and friends) come back sorted.
- `TrieMap` adds values via `set`/`get`; the prefix words still apply.
- All four variants share one API — switch by changing the import.

## Where to go next

- Solve specific problems with the [How-to guides](how-to.md) — including
  how to choose a variant.
- Look up exact signatures in the [Reference](reference.md).
- Understand how each variant works in the [Explanation](explanation.md).
