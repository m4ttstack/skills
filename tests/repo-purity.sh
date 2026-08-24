#!/bin/sh
# repo-purity.sh -- the whole tracked tree greps clean of domain terms.
# Hard rule (Matt, 2026-08-18): no domain references anywhere in mattstack,
# not just in skill text. Per-skill certification (certify.sh) still gates
# each skill dir; this sweeps everything git tracks, so program artifacts,
# docs, fixtures, and configs are held to the same line.
# Run bare from anywhere: tests/repo-purity.sh. Exit 0 = clean.
set -u
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/.." && pwd)

# Assembled from fragments so this repo greps clean for its own banned words
# (same technique as certify.sh).
A1=$(printf '%s%s' 'ass' 'ured')
A2=$(printf '%s%s' 'claim' 'view')
A3=$(printf '%s%s' 'cv-' '[0-9]')
A4=$(printf '%s%s' 'strong' 'dm')
A5=$(printf '%s%s' 'launch' 'darkly')
A6=$(printf '%s%s' 'parking' '-lot')

HITS=$(cd "$ROOT" && git ls-files -z | xargs -0 grep -niE "$A1|$A2|$A3|$A4|$A5|$A6" 2>/dev/null || true)
if [ -n "$HITS" ]; then
  echo "FAIL repo-purity:"
  printf '%s\n' "$HITS"
  exit 1
fi
echo "ok   repo-purity"
