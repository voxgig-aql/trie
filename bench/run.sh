#!/bin/bash
# Time the trie benchmark under the interpreter and the bytecode compiler,
# across a series of key counts. Reports best-of-1 wall time. Requires `boru`
# on PATH. Run from anywhere; imports resolve relative to the repo root, so
# this script cd's there and invokes the bench by path.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
BENCH=bench/trie_bench.aql
SIZES="${SIZES:-500 1000 2000}"
orig=$(grep '^def N ' "$BENCH")
timerun() { local mode="$1" s e; s=$(date +%s.%N); boru "$mode" "$BENCH" >/dev/null 2>&1; e=$(date +%s.%N); awk "BEGIN{printf \"%.2f\", $e-$s}"; }
printf "%-8s %-14s %-14s %-8s\n" "N" "interp(s)" "compiled(s)" "speedup"
for n in $SIZES; do
  sed -i "s/^def N .*/def N $n/" "$BENCH"
  i=$(timerun --no-compile); c=$(timerun --compile)
  sp=$(awk "BEGIN{printf \"%.2fx\", $i/$c}")
  printf "%-8s %-14s %-14s %-8s\n" "$n" "$i" "$c" "$sp"
done
sed -i "s/^def N .*/$orig/" "$BENCH"
