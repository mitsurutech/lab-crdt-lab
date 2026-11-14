#!/usr/bin/env bash
# What compose.yaml's header promises, checked from inside the lab's own network and through
# docker exec, which is how the platform's terminal reaches the lab's Python: run by check.sh.
set -euo pipefail
: "${NET:?run through test/check.sh}"
: "${CID:?run through test/check.sh}"
probe() { docker run --rm --network "$NET" lab-check-probe bash -c "$1"; }
run() { docker exec "$CID" "$@"; }
# Every step is the same each time (fixed text and fixed seeds), so the output is held exactly.
expect() { # expect <name> <text that must be a line of the output>...
  local out; out=$(run python3 "steps/$1.py"); shift
  for want in "$@"; do
    echo "$out" | grep -Fxq -- "$want" || { echo "missing '$want' in: $out" >&2; exit 1; }
  done
}

echo "- JupyterLab answers with no token to type"
probe '
set -eu
code=$(curl -s -o /dev/null -w "%{http_code}" http://jupyter:8888/lab)
[ "$code" = 200 ] || { echo "JupyterLab answered $code" >&2; exit 1; }
curl -fs http://jupyter:8888/api/contents | grep -q "start.ipynb" || { echo "no start.ipynb" >&2; exit 1; }
curl -fs -H "Host: someone-8888.example.com" -H "Origin: https://someone-8888.example.com" \
  http://jupyter:8888/api/kernelspecs | grep -q python3 || { echo "a proxied host is refused" >&2; exit 1; }
echo "- no way out to the internet"
if curl -s -m 4 -o /dev/null https://example.com; then echo "the lab reached the internet" >&2; exit 1; fi
'

echo "- the work folder holds the modules, the notebook and the step scripts"
run ls crdt.py rga.py start.ipynb steps/lostedit.py steps/gcounter.py steps/pncounter.py \
  steps/register.py steps/orset.py steps/text.py steps/interleave.py steps/clocks.py \
  steps/delta.py steps/tombstones.py steps/offline.py >/dev/null

echo "- lostedit.py: whole-note last writer wins loses an edit, field by field keeps both"
expect lostedit \
  "naive sync keeps: {'title': 'Trip', 'body': 'Pack bags, book hotel'}" \
  "phone's title edit lost: True" \
  "field by field: {'title': 'Trip to York', 'body': 'Pack bags, book hotel'}"

echo "- gcounter.py: three replicas agree whatever the order, and a repeat changes nothing"
expect gcounter \
  "before sync: 3 5 2" \
  "phone sees 10 {'phone': 3, 'laptop': 5, 'tablet': 2}" \
  "after merging twice more: 10" \
  "plain number after a repeated message: 19"

echo "- pncounter.py: ups and downs merge to one value"
expect pncounter \
  "a alone: 3  b alone: 0" \
  "after sync: a = 3 b = 3"

echo "- register.py: the later stamp wins, a tie is broken by name, a slow clock loses"
expect register \
  "both keep: green green (105, 'laptop')" \
  "tie at 200 keeps: gold gold" \
  "after the slow phone writes purple, laptop keeps: green"

echo "- orset.py: a concurrent add wins over a remove"
expect orset \
  "ana: ['eggs']  ben: ['eggs', 'milk']" \
  "after sync, ana: ['eggs', 'milk']  ben: ['eggs', 'milk']" \
  "after Ben removes milk with every tag seen: ['eggs']"

echo "- text.py: two offline edits to one line merge to the same text"
expect text \
  "after sync, ana: Oh, ello world" \
  "after sync, ben: Oh, ello world" \
  "tombstones kept: 1"

echo "- interleave.py: numbers between neighbours interleave, RGA keeps words whole"
expect interleave \
  "numbers between neighbours: cdaotg" \
  "RGA: dogcat dogcat"

echo "- clocks.py: before, after, equal and concurrent"
expect clocks \
  "a = {'a': 1}  b = {'b': 1}  a vs b: concurrent" \
  "b after hearing a: {'a': 1, 'b': 2}  a vs b: before" \
  "a vs a: equal"

echo "- delta.py: a delta is far smaller than the whole state"
expect delta \
  "full state: 7890 bytes" \
  'delta: 29 bytes {"device3": 6, "device42": 2}' \
  "friend after the delta: 1997  hub: 1997"

echo "- tombstones.py: tombstones stay until they can be dropped"
expect tombstones \
  "visible: 10  stored: 200  tombstones: 190" \
  "compacted once every replica has seen them: 190" \
  "deleted at the start, compacted: 0  tombstones still needed: 190"

echo "- offline.py: three replicas converge after random offline edits"
expect offline \
  "phone after sync: ['jam', 'oats', 'rice', 'soap', 'tea'] 28" \
  "laptop after sync: ['jam', 'oats', 'rice', 'soap', 'tea'] 28" \
  "tablet after sync: ['jam', 'oats', 'rice', 'soap', 'tea'] 28"

echo "- the starter notebook runs from top to bottom inside the memory limit"
run jupyter nbconvert --to notebook --execute start.ipynb --output /tmp/ran.ipynb >/dev/null 2>&1 \
  || { echo "start.ipynb does not run" >&2; exit 1; }
echo "  ok"
