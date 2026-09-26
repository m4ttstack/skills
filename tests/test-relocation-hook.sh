#!/bin/sh
# Exercises hooks/relocation-announce.sh with a PATH-stubbed rt: the hook
# must exit 0 and print nothing, forward the hook's stdin verbatim to
# `rt worktree announce-relocation`, and still exit 0 with no rt anywhere.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$ROOT/hooks/relocation-announce.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/bin" "$TMP/home"
cat > "$TMP/bin/rt" <<'FAKE'
#!/bin/sh
printf '%s\n' "$*" > "$FAKE_ARGV"
cat > "$FAKE_STDIN"
FAKE
chmod +x "$TMP/bin/rt"

PAYLOAD='{"hook_event_name":"PreToolUse","tool_name":"EnterWorktree","session_id":"sess-1","cwd":"/tmp/repo"}'

out=$(printf '%s' "$PAYLOAD" | \
  PATH="$TMP/bin:$PATH" FAKE_ARGV="$TMP/argv" FAKE_STDIN="$TMP/stdin" \
  sh "$HOOK" 2>&1)
code=$?
[ "$code" -eq 0 ] || { echo "FAIL: exit code $code"; exit 1; }
[ -z "$out" ] || { echo "FAIL: hook printed output: $out"; exit 1; }

argv="$(cat "$TMP/argv")"
[ "$argv" = "worktree announce-relocation" ] || {
  echo "FAIL: rt not called with worktree announce-relocation (got: $argv)"; exit 1;
}

stdin_seen="$(cat "$TMP/stdin")"
[ "$stdin_seen" = "$PAYLOAD" ] || {
  echo "FAIL: rt did not receive the hook stdin (got: $stdin_seen)"; exit 1;
}

# No rt on PATH and no ~/.local/bin/rt: the dialog falls to the human, not a
# blocked tool call.
out2=$(printf '%s' "$PAYLOAD" | PATH="/usr/bin:/bin" HOME="$TMP/home" sh "$HOOK" 2>&1)
code2=$?
[ "$code2" -eq 0 ] || { echo "FAIL: no-rt case exit code $code2"; exit 1; }
[ -z "$out2" ] || { echo "FAIL: no-rt case printed output: $out2"; exit 1; }

echo "ok"
