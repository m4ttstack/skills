#!/usr/bin/env bash
# Launch a Claude Code agent in a fresh herdr pane, under a chosen cswap account
# and model, in a target repo, and (by default) enable /remote-control so the
# session can be continued from your phone or claude.ai/code.
#
# Usage:
#   remote-agent.sh -r <repo-name|path> [-a <account>] [-m <model>]
#                   [-t] [-d <direction>] [-R]
#
#   -r  Target repo: a name resolved under ~/Documents/GitHub, or an absolute
#       path. Required.
#   -a  cswap account (email or list number). Default: current active account
#       (launches plain `claude`, no cswap wrapper).
#   -m  Model alias passed as `claude --model <model>`. Default: opus.
#       Pass -m "" to inherit Claude's default model.
#   -t  Open a new herdr TAB (labeled after the repo) instead of splitting a
#       pane. Default: split a pane off the focused pane.
#   -d  Split direction when not using -t: right|down|left|up. Default: right.
#   -R  Do NOT send /remote-control. Default: send it and print the session URL.
#
# Prints a summary block on stdout (pane id, account, model, repo, remote URL).
# All progress/logging goes to stderr. Exit non-zero on any hard failure.
set -euo pipefail

usage() { sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

REPO=""
ACCOUNT=""
MODEL="opus"
NEW_TAB=0
DIRECTION="right"
REMOTE=1
while getopts "r:a:m:td:Rh" opt; do
  case "$opt" in
    r) REPO="$OPTARG" ;;
    a) ACCOUNT="$OPTARG" ;;
    m) MODEL="$OPTARG" ;;
    t) NEW_TAB=1 ;;
    d) DIRECTION="$OPTARG" ;;
    R) REMOTE=0 ;;
    *) usage ;;
  esac
done

log() { echo "remote-agent: $*" >&2; }

# 1. Must be inside herdr.
[ "${HERDR_ENV:-}" = "1" ] || { echo "remote-agent: not inside herdr (HERDR_ENV != 1). Run this from a herdr-managed pane." >&2; exit 1; }
command -v herdr >/dev/null || { echo "remote-agent: herdr not on PATH" >&2; exit 1; }

# 2. Resolve the target repo path.
: "${REPO:?-r <repo-name|path> is required}"
if [ -d "$REPO" ]; then
  REPO_PATH="$(cd "$REPO" && pwd)"
elif [ -d "$HOME/Documents/GitHub/$REPO" ]; then
  REPO_PATH="$HOME/Documents/GitHub/$REPO"
else
  echo "remote-agent: repo not found: '$REPO' (looked at the path and ~/Documents/GitHub/$REPO)" >&2
  exit 1
fi
REPO_NAME="$(basename "$REPO_PATH")"
log "repo -> $REPO_PATH"

# 3. Validate the cswap account if one was requested.
if [ -n "$ACCOUNT" ]; then
  command -v cswap >/dev/null || { echo "remote-agent: cswap not on PATH but -a was given" >&2; exit 1; }
  if ! cswap list 2>/dev/null | grep -qiF "$ACCOUNT"; then
    echo "remote-agent: cswap account '$ACCOUNT' not found. Known accounts:" >&2
    cswap list >&2 || true
    exit 1
  fi
  log "account -> $ACCOUNT (via cswap run)"
else
  log "account -> current active (no cswap wrapper)"
fi

# 4. Find the focused pane (ours) and its workspace.
read -r FOCUSED_PANE FOCUSED_WS < <(herdr pane list | python3 -c '
import sys, json
r = json.load(sys.stdin)
r = r.get("result", r)
panes = r["panes"]
f = next((p for p in panes if p.get("focused")), None) or panes[0]
print(f["pane_id"], f["workspace_id"])
')
log "focused pane $FOCUSED_PANE (workspace $FOCUSED_WS)"

# 5. Create the target pane -- new tab or a split.
if [ "$NEW_TAB" = "1" ]; then
  PANE="$(herdr tab create --workspace "$FOCUSED_WS" --label "$REPO_NAME" --no-focus \
    | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"]["root_pane"]["pane_id"])')"
  log "opened new tab, pane $PANE"
else
  PANE="$(herdr pane split "$FOCUSED_PANE" --direction "$DIRECTION" --no-focus \
    | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"]["pane"]["pane_id"])')"
  log "split pane $PANE ($DIRECTION)"
fi

# 6. Build and run the launch command. --share-history is not optional: cswap
#    re-syncs sharing on every launch, so a run without it unlinks that
#    account's projects/ and history.jsonl and the session lands in a profile-
#    local transcript dir that `claude --resume` elsewhere cannot see.
LAUNCH="claude"
[ -n "$MODEL" ] && LAUNCH="$LAUNCH --model '$MODEL'"
[ -n "$ACCOUNT" ] && LAUNCH="cswap run '$ACCOUNT' --share-history -- $LAUNCH"
herdr pane run "$PANE" "cd '$REPO_PATH' && $LAUNCH"
log "launching: cd '$REPO_PATH' && $LAUNCH"

# 7. Wait for readiness. agent-status idle is robust; matching banner text is
#    not (the banner wording varies by version/model). cswap's account switch
#    can add a few seconds, so allow a generous timeout.
if ! herdr wait agent-status "$PANE" --status idle --timeout 60000 >/dev/null 2>&1; then
  log "agent-status idle wait timed out; falling back to prompt match"
  herdr wait output "$PANE" --match "auto mode|❯" --regex --timeout 20000 >/dev/null 2>&1 \
    || log "readiness could not be confirmed for $PANE -- check the pane manually"
fi

# 8. Enable /remote-control unless suppressed, and capture the session URL.
# Read the pane with all whitespace stripped. Panes can be narrow, and Claude
# wraps both the "is active" line and the session URL across rows; stripping
# whitespace lets a single regex match them regardless of wrap width.
snap_stripped() { herdr pane read "$PANE" --source recent-unwrapped --lines 80 2>/dev/null | tr -d '[:space:]'; }

REMOTE_URL=""
if [ "$REMOTE" = "1" ]; then
  activated=0
  # Up to 3 attempts. Each attempt first waits for a settled idle -- the startup
  # auto-greeting (some configs "bake" for ~20s) makes the FIRST idle fire before
  # the greeting finishes, so a command sent then is lost. Re-waiting idle and
  # re-sending the full text (not just an Enter nudge) rides out that race.
  for attempt in 1 2 3; do
    herdr wait agent-status "$PANE" --status idle --timeout 30000 >/dev/null 2>&1 || true
    herdr pane send-text "$PANE" "/remote-control"
    herdr pane send-keys "$PANE" Enter
    # Poll ~20s for activation, pacing with 1s waits (no sleep dependency).
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
      S="$(snap_stripped)"
      REMOTE_URL="$(printf '%s' "$S" | grep -oE 'https://claude\.ai/code/session[_A-Za-z0-9-]+' | head -1 || true)"
      if [ -n "$REMOTE_URL" ] || printf '%s' "$S" | grep -q 'remote-controlisactive'; then activated=1; break; fi
      herdr wait output "$PANE" --match "remote-control is active" --timeout 1000 >/dev/null 2>&1 || true
    done
    [ "$activated" = "1" ] && break
    # Text may have sat unsubmitted (paste detection); nudge before retrying.
    herdr pane send-keys "$PANE" Enter
  done
  if [ "$activated" = "1" ]; then
    log "/remote-control active"
  else
    log "/remote-control sent but activation was not confirmed -- read the pane to check"
  fi
fi

# 9. Summary on stdout.
cat <<EOF
pane: $PANE
repo: $REPO_PATH
account: ${ACCOUNT:-<current active>}
model: ${MODEL:-<claude default>}
remote_control: $([ "$REMOTE" = "1" ] && echo enabled || echo skipped)
remote_url: ${REMOTE_URL:-<none>}
EOF
