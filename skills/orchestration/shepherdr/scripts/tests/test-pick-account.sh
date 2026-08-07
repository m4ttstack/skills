#!/usr/bin/env bash
# Offline tests for pick-account.py against a fixture of cswap list --json.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PICK="$DIR/../pick-account.py"
FIX="$(mktemp)"; trap 'rm -f "$FIX"' EXIT
cat > "$FIX" <<'JSON'
{"schemaVersion": 1, "accounts": [
  {"number": 1, "email": "a@example.com", "usage": {
    "fiveHour": {"pct": 0.0}, "sevenDay": {"pct": 88.0},
    "scoped": [{"name": "Fable", "pct": 100.0}]}},
  {"number": 2, "email": "b@example.com", "usage": {
    "fiveHour": {"pct": 13.0}, "sevenDay": {"pct": 49.0},
    "scoped": [{"name": "Fable", "pct": 51.0}]}},
  {"number": 3, "email": "c@example.com", "usage": {
    "fiveHour": {"pct": 17.0}, "sevenDay": {"pct": 38.0},
    "scoped": [{"name": "Fable", "pct": 55.0}]}}
]}
JSON

fails=0
check() { # name expected_stdout expected_exit actual_stdout actual_exit
  if [ "$4" = "$2" ] && [ "$5" -eq "$3" ]; then echo "ok   $1"
  else echo "FAIL $1 (want '$2'/$3 got '$4'/$5)"; fails=$((fails+1)); fi
}

out=$("$PICK" --pool 2,3 --json-file "$FIX" --threshold 90 2>/dev/null); rc=$?
check "lowest binding wins (no model)" "3" 0 "$out" "$rc"
# 3: max(17,38)=38 beats 2: max(13,49)=49

out=$("$PICK" --pool 2,3 --model claude-fable-5 --json-file "$FIX" --threshold 90 2>/dev/null); rc=$?
check "scoped limit binds" "2" 0 "$out" "$rc"
# with Fable scoped: 2 -> max(13,49,51)=51 beats 3 -> max(17,38,55)=55

out=$("$PICK" --pool 1,2 --model Fable --json-file "$FIX" --threshold 90 2>/dev/null); rc=$?
check "over-threshold excluded" "2" 0 "$out" "$rc"
# 1's Fable=100 >= 90 -> excluded even though its 5h is 0

out=$("$PICK" --pool 2,3 --assigned 3,3 --json-file "$FIX" --threshold 90 2>/dev/null); rc=$?
check "spread penalty shifts pick" "3" 0 "$out" "$rc"
# 3: 38 + 2*5 = 48 vs 2: 49 ... still 3? -> 48 < 49, so bump: assigned 3,3,3
out=$("$PICK" --pool 2,3 --assigned 3,3,3 --json-file "$FIX" --threshold 90 2>/dev/null); rc=$?
check "spread penalty shifts pick (3 panes)" "2" 0 "$out" "$rc"
# 3: 38 + 15 = 53 vs 2: 49 -> 2 wins

out=$("$PICK" --pool 1 --model Fable --json-file "$FIX" --threshold 90 2>/dev/null); rc=$?
check "all excluded exits nonzero" "" 1 "$out" "$rc"

[ "$fails" -eq 0 ] && echo "all tests passed" || exit 1
