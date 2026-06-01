# trie

A small, dependency-light set of **trie (prefix tree) utilities**
implemented in [AQL](https://github.com/aql-lang/aql). One import gives
you fast prefix search, autocomplete, and longest-prefix matching over
String keys — as either a **set** of keys or a **map** from keys to
values — in four classic flavours.

```aql
import "./trie.aql"

def t (((TrieSet.make end) "cat" TrieSet.add end) "car" TrieSet.add end)

(t "car" TrieSet.has end)            print   # => true
(t "ca"  TrieSet.with-prefix end)    print   # => ["car", "cat"]
(t "cartoon" TrieSet.longest-prefix end) print  # => "car"
```

## The four variants

Each variant ships in its own file and exports **two namespaces** — a
`…Set` (membership) and a `…Map` (key → value) — over a shared engine.
They are behaviourally interchangeable (the property tests cross-check
them against the standard trie); pick one by its space/shape trade-off.

| File | Namespaces | What it is | Reach for it when… |
|------|------------|------------|--------------------|
| [`trie.aql`](trie.aql)   | `TrieSet` / `TrieMap`   | **Standard trie** — one node per character | the default; simplest and predictable |
| [`radix.aql`](radix.aql) | `RadixSet` / `RadixMap` | **Radix / PATRICIA tree** — single-child chains compressed into edge labels | keys are long and sparse; you want fewer nodes |
| [`tst.aql`](tst.aql)     | `TstSet` / `TstMap`     | **Ternary search tree** — BST-of-characters hybrid | the alphabet is large; you want few pointers per node |
| [`burst.aql`](burst.aql) | `BurstSet` / `BurstMap` | **Burst trie (HAT-trie family)** — flat buckets that burst into trie nodes | you want cache-friendly buckets over a shallow spine |

## The common API at a glance

Every namespace shares the same surface (set words on the left, the
extra map words on the right). `Xxx` is any of the eight namespaces.

| Set / map word | Purpose |
|----------------|---------|
| `Xxx.make`                    | build an empty trie |
| `t k Xxx.add` *(set)* / `t k v Xxx.set` *(map)* | insert a key (with a value) → new trie |
| `t k Xxx.has`                 | membership test → Boolean |
| `t k Xxx.get` *(map)*         | value for a key, or `none` |
| `t k Xxx.delete`              | remove a key → new trie |
| `t p Xxx.with-prefix` *(set)* / `Xxx.keys-with-prefix` *(map)* | all keys under prefix `p` |
| `t k Xxx.longest-prefix`      | longest stored key that prefixes `k` |
| `t Xxx.keys`                  | all keys, sorted |
| `t Xxx.values` / `Xxx.entries` *(map)* | all values / `[key, value]` pairs |
| `t Xxx.size` / `Xxx.height`   | key count / structural depth |
| `keys Xxx.from-keys` *(set)* / `entries Xxx.from-entries` *(map)* | rebuild a trie from extracted data (inverse of `keys`/`entries`) |
| `t Xxx.encode`                | jsonic-style snapshot string |

The standard trie additionally offers two **advanced queries**:
`t query k TrieSet.within` (fuzzy / edit-distance search) and
`t pattern TrieSet.match` (wildcard search, `?` = one char, `*` = any run).

Tries are **persistent (immutable)**: every `add`/`set`/`delete` returns
a *new* trie and leaves the input untouched. Every call ends with `end`
(or is wrapped in parens) — standard AQL forward-dispatch. Full details
and the calling convention are in the [Reference](docs/reference.md).

## Documentation

The docs follow the [Diátaxis](https://diataxis.fr) framework — four
modes, each serving a different need:

| | Mode | Read this when you want to… |
|--|------|----------------------------|
| 🎓 | **[Tutorial](docs/tutorial.md)** | learn by building your first trie step by step |
| 🔧 | **[How-to guides](docs/how-to.md)** | accomplish a task (autocomplete, choose a variant, persist, test…) |
| 📖 | **[Reference](docs/reference.md)** | look up exact words, signatures, and return types |
| 💡 | **[Explanation](docs/explanation.md)** | understand how each variant works and why it's built this way |

**For AI coding agents:** start with [`CLAUDE.md`](CLAUDE.md) (also available as
[`AGENTS.md`](AGENTS.md)) — a compact guide to importing, calling, and the AQL
foot-guns to avoid. A machine-readable API manifest is in [`api.json`](api.json).

New here? Start with the [Tutorial](docs/tutorial.md). Just want the API?
Jump to the [Reference](docs/reference.md).

## Project layout

```
trie.aql                  standard trie        (TrieSet,  TrieMap)
radix.aql                 radix / PATRICIA     (RadixSet, RadixMap)
tst.aql                   ternary search tree  (TstSet,   TstMap)
burst.aql                 burst / HAT trie     (BurstSet, BurstMap)
test/smoke.aql                smoke demo across all four variants
test/<variant>_test.aql       example-based unit tests
test/<variant>_prop_spec.aql  property-based tests (declarative spec form)
test/trie_pbt.aql             property-based tests (direct test.check-prop form)
docs/                     Diátaxis documentation (above)
DX-REPORT.md              developer-experience notes on building this in AQL
```

## Running it

Build the `aql` interpreter, then run the demo or any test — see
[How-to → Install and run](docs/how-to.md#install-and-run-aql):

```bash
aql test/smoke.aql             # smoke demo
aql test/trie_test.aql         # unit tests (one suite per variant)
aql test/trie_prop_spec.aql    # property tests
```

A GitHub Actions workflow ([`ci/test.yml`](ci/test.yml)) builds aql from
a pinned commit and runs every suite on each push and pull request. It is
staged under `ci/` rather than `.github/workflows/` because the token
that created this branch lacked GitHub `workflow` scope; move it into
place to activate it — see [`ci/README.md`](ci/README.md).

## License

See [LICENSE](LICENSE).
