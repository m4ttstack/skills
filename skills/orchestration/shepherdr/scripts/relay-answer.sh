#!/usr/bin/env bash
# Relay an answer to an agent pane: clear any auto-drafted input, then send.
# Agents in auto mode often draft a suggested answer into their own input
# buffer; sending Enter would submit the draft, not your answer. Always
# ctrl+c first, then run.
#
# Usage: relay-answer.sh <pane-id> <answer text...>
set -euo pipefail
[ $# -ge 2 ] || { echo "usage: relay-answer.sh <pane-id> <answer text...>" >&2; exit 2; }

# Routed through the shim so the same relay works whether the agent is in a
# visible pane or an invisible herd session. See scripts/hrd.
HRD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hrd"

PANE="$1"; shift
"$HRD" pane send-keys "$PANE" ctrl+c
sleep 1
"$HRD" pane run "$PANE" "$*"

# Paste detection can swallow the submit, leaving the answer in the input
# box. Confirm the agent went back to work; nudge with Enter if it did not.
if ! "$HRD" agent wait "$PANE" --until working --timeout 8000 >/dev/null 2>&1; then
  "$HRD" pane send-keys "$PANE" Enter
fi
