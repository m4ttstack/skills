#!/usr/bin/env bash
# Surface one invisible herd pane in the visible session so the user can
# intervene, then get out of the way again.
#
# Usage:
#   attend.sh <herd-pane-id> [-s <session>] [-l <label>] [-c <cols>] [-r <rows>]
#
# Herd panes live in a separate herdr server, and panes cannot move between
# servers. So this does not relocate the agent: it opens a tab in the visible
# session and streams the herd pane into it, writable, via `terminal session
# control --takeover`. The agent never moves or restarts; the user is just
# looking at it through a window.
#
# A tab, not a split: the stream renders at whatever geometry the controller
# is given, and a full tab is the one surface guaranteed to fit it.
#
# The size is computed by the receiving pane's own shell (`tput cols`), not
# here, because only that shell knows how big the tab actually is. That size
# is then pushed onto the herd pane, which keeps it after detach -- so
# attending also permanently rescues a pane from the headless default.
# -c/-r override.
#
# Detach with ctrl+b q. The tab is left open (the user may want to look
# again); the shepherd closes it with `herdr tab close <tab-id>` when the
# intervention is resolved. Prints "<tab-id> <pane-id>" for the visible tab
# on stdout, so the shepherd can clean up without guessing.
set -euo pipefail

SESSION="${SHEPHERDR_HERD_SESSION:-herd}"
LABEL=""
COLS=""
ROWS=""
TARGET="${1:-}"
[ $# -gt 0 ] && shift
while getopts "s:l:c:r:" opt; do
  case "$opt" in
    s) SESSION="$OPTARG" ;;
    l) LABEL="$OPTARG" ;;
    c) COLS="$OPTARG" ;;
    r) ROWS="$OPTARG" ;;
    *) sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
  esac
done
[ -n "$TARGET" ] || { echo "attend: <herd-pane-id> required" >&2; exit 2; }

# Confirm the target exists before building a tab around it, so a stale pane
# id fails here with a clear message instead of as a dead stream the user has
# to diagnose from the inside.
if ! env -u HERDR_SOCKET_PATH HERDR_SESSION="$SESSION" herdr pane get "$TARGET" >/dev/null 2>&1; then
  echo "attend: pane $TARGET not found in herd session '$SESSION'" >&2
  exit 1
fi

# The visible session: plain herdr, no session override, inheriting this
# pane's injected socket. This is the one place in shepherdr that must NOT
# route through scripts/hrd.
read -r TAB PANE < <(
  herdr tab create --workspace "$HERDR_WORKSPACE_ID" --label "attend: ${LABEL:-$TARGET}" --focus \
    | python3 -c 'import sys,json; r=json.load(sys.stdin)["result"]; print(r["tab"]["tab_id"], r["root_pane"]["pane_id"])'
)

# Unescaped $(tput ...) on purpose: it must be evaluated by the new pane's
# shell, which is the only thing that knows the tab's real dimensions.
herdr pane run "$PANE" \
  "env -u HERDR_SOCKET_PATH HERDR_SESSION=$SESSION herdr terminal session control $TARGET --takeover --cols ${COLS:-\$(tput cols)} --rows ${ROWS:-\$(tput lines)}"

echo "attend: streaming herd pane $TARGET into $PANE (detach with ctrl+b q)" >&2
echo "$TAB $PANE"
