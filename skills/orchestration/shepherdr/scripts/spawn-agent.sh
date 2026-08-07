#!/usr/bin/env bash
# Spawn one shepherdr agent: worktree + herdr tab + claude + kickoff prompt.
#
# Usage:
#   spawn-agent.sh -j <job-name> (-b <branch> | -d <existing-dir>) -J <brief.md>
#                  -w <workspace-id> [-r <repo-root>] [-k <kickoff-text>]
#                  [-m <model>] [-a <cswap-account>]
#
# With -b: creates the worktree at ~/.shepherdr/worktrees/<repo>/<job-name>.
# With -d: uses the existing directory as-is (no git worktree add); any branch
# must already be provisioned there. -m launches claude with --model <model>.
# -a launches through `cswap run <account> --` so the pane bills that account.
# Copies the brief to the job dir ~/.shepherdr/jobs/<repo>/<job-name>/job.md
# (contract files never live inside the repo), opens a --no-focus tab labeled
# "<worktree>: <job>" in the given workspace, launches claude, waits for
# readiness (auto-accepting claude's fresh-worktree trust dialog), names
# the agent after the job, and submits the kickoff via `agent prompt`
# (atomic under bracketed paste; delivery-verified, resent once).
# Prints "<pane-id> <target>" on stdout; target is the agent name when the
# job name fits herdr's name grammar, else the pane id. Everything else goes
# to stderr.
#
# With SHEPHERDR_HERD_SESSION set, the tab is created in that invisible herd
# session instead of the visible one; -w must then be a workspace id from
# that session. Nothing else about the call changes.
set -euo pipefail

# All herdr traffic goes through the shim, which is what makes the visible /
# invisible switch a single env var. See scripts/hrd.
HRD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hrd"

usage() { sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

REPO_ROOT=""
KICKOFF=""
BRANCH=""
DIR=""
MODEL=""
ACCOUNT=""
while getopts "j:b:J:w:r:k:d:m:a:" opt; do
  case "$opt" in
    j) JOB="$OPTARG" ;;
    b) BRANCH="$OPTARG" ;;
    J) JOB_MD="$OPTARG" ;;
    w) WORKSPACE="$OPTARG" ;;
    r) REPO_ROOT="$OPTARG" ;;
    k) KICKOFF="$OPTARG" ;;
    d) DIR="$OPTARG" ;;
    m) MODEL="$OPTARG" ;;
    a) ACCOUNT="$OPTARG" ;;
    *) usage ;;
  esac
done
: "${JOB:?-j job-name required}"
: "${JOB_MD:?-J job brief path required}" "${WORKSPACE:?-w workspace id required}"
if [ -n "$DIR" ] && [ -n "$BRANCH" ]; then echo "spawn-agent: -b and -d are mutually exclusive" >&2; exit 2; fi
if [ -z "$DIR" ] && [ -z "$BRANCH" ]; then echo "spawn-agent: one of -b <branch> or -d <existing-dir> is required" >&2; exit 2; fi
[ -f "$JOB_MD" ] || { echo "job brief not found: $JOB_MD" >&2; exit 1; }

if [ -n "$DIR" ]; then
  [ -d "$DIR" ] || { echo "directory not found: $DIR" >&2; exit 1; }
  WORKTREE="$DIR"
  REPO_NAME="$(basename "$DIR")"
else
  [ -n "$REPO_ROOT" ] || REPO_ROOT="$(git rev-parse --show-toplevel)"
  REPO_NAME="$(basename "$REPO_ROOT")"
  WORKTREE="$HOME/.shepherdr/worktrees/$REPO_NAME/$JOB"
  mkdir -p "$(dirname "$WORKTREE")"
  git -C "$REPO_ROOT" worktree add "$WORKTREE" -b "$BRANCH" >&2
fi

# Contract files live outside the repo: zero worktree footprint.
JOB_DIR="$HOME/.shepherdr/jobs/$REPO_NAME/$JOB"
mkdir -p "$JOB_DIR"
cp "$JOB_MD" "$JOB_DIR/job.md"
echo "spawn-agent: job dir $JOB_DIR" >&2

# The sidebar label is how the user finds where a job lives: worktree name
# first, then the job. Collapses to the job name when they are the same word
# (-b mode names the worktree after the job).
WT_NAME="$(basename "$WORKTREE")"
if [ "$WT_NAME" = "$JOB" ]; then LABEL="$JOB"; else LABEL="$WT_NAME: $JOB"; fi

PANE="$("$HRD" tab create --workspace "$WORKSPACE" --label "$LABEL" --no-focus \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"]["root_pane"]["pane_id"])')"

# A herd session has no client, so its panes are born at the server's
# no-client default of 53x23 -- unusable for a Claude TUI, and it hard-wraps
# every `pane read`. A one-shot takeover controller sets the real grid and
# the size persists after it detaches (0.2s, verified on 0.7.5). Visible
# panes are left alone: there the UI layout owns the size.
if [ -n "${SHEPHERDR_HERD_SESSION:-}" ]; then
  "$HRD" terminal session control "$PANE" --takeover \
    --cols "${SHEPHERDR_HERD_COLS:-200}" --rows "${SHEPHERDR_HERD_ROWS:-50}" \
    </dev/null >/dev/null 2>&1 \
    || echo "spawn-agent: could not resize herd pane $PANE; TUI may render cramped" >&2
fi

"$HRD" pane run "$PANE" "cd $WORKTREE"
if [ -n "$ACCOUNT" ]; then
  "$HRD" pane run "$PANE" "cswap run $ACCOUNT --${MODEL:+ --model '$MODEL'}"
else
  "$HRD" pane run "$PANE" "claude${MODEL:+ --model '$MODEL'}"
fi

# herdr needs a brief moment after the launch command to attach the
# freshly started claude process as a tracked agent session; calling
# `agent wait` before that registration lands returns agent_not_found
# immediately instead of polling for the agent to appear (live-verified:
# it is reliably still missing at 0.3s and present by 0.6s). Poll briefly
# for the agent to be known before the real readiness wait below.
for _ in $(seq 1 20); do
  "$HRD" agent get "$PANE" >/dev/null 2>&1 && break
  sleep 0.25
done

# Readiness: wait for herdr to detect the agent and see it settled or
# blocked. A fresh worktree makes claude open its "do you trust this
# folder?" dialog, which herdr reports as blocked; accept it (the shepherd
# created this worktree itself, so trust is correct by construction) and
# re-wait. Task-1 probing showed a blocked agent silently discards
# prompted text, so this MUST resolve before the kickoff.
"$HRD" agent wait "$PANE" --until idle --until done --until blocked --timeout 45000 >/dev/null \
  || { echo "spawn-agent: agent never became ready in pane $PANE" >&2; exit 1; }
STATUS="$("$HRD" agent get "$PANE" \
  | python3 -c 'import sys,json; r=json.load(sys.stdin)["result"]; a=r.get("agent") or r; print(a.get("agent_status","unknown"))' \
  2>/dev/null || echo unknown)"
if [ "$STATUS" = "blocked" ]; then
  if "$HRD" agent read "$PANE" --source visible --lines 30 | grep -qi "trust"; then
    "$HRD" agent send-keys "$PANE" enter
    "$HRD" agent wait "$PANE" --until idle --until done --timeout 30000 >/dev/null \
      || { echo "spawn-agent: agent stuck after trust dialog in pane $PANE" >&2; exit 1; }
  else
    echo "spawn-agent: agent blocked on an unrecognized dialog in pane $PANE" >&2
    exit 1
  fi
fi

# Name the agent after its job so the shepherd targets names, not pane ids.
# herdr names must match [a-z][a-z0-9_-]{0,31} and be unique among live
# agents; fall back to the pane id when the job name does not qualify.
TARGET="$PANE"
if [[ "$JOB" =~ ^[a-z][a-z0-9_-]{0,31}$ ]] \
   && "$HRD" agent rename "$PANE" "$JOB" >/dev/null 2>&1; then
  TARGET="$JOB"
else
  echo "spawn-agent: could not name agent '$JOB'; targeting pane id" >&2
fi

if [ -z "$KICKOFF" ]; then
  KICKOFF="Your job directory is $JOB_DIR -- it is outside the repo, and all job/question/report and scratch files belong there, NEVER in the repo or worktree. Read $JOB_DIR/job.md and complete the entire job it describes. Work only inside this worktree and stay within the brief's scope fence. The brief's verification commands must pass. Whenever you need input from Matt, write $JOB_DIR/question.md in the multiple-choice format the brief shows, then stop and wait; the answer arrives as your next message. Even yes/no confirmations become numbered options. When the job is complete, write $JOB_DIR/report.md per the brief, then stop. Commit incrementally on this branch; never push. The worktree must contain only the work itself."
fi

# `agent prompt` submits atomically under bracketed paste. Task-1 probing
# showed its stall error cannot be relied on (a blocked agent discards the
# text with exit 0), so verify delivery by watching for `working`; resend
# once if it never starts.
"$HRD" agent prompt "$TARGET" "$KICKOFF" >/dev/null
if ! "$HRD" agent wait "$TARGET" --until working --timeout 8000 >/dev/null 2>&1; then
  echo "spawn-agent: kickoff not picked up; resending once" >&2
  "$HRD" agent prompt "$TARGET" "$KICKOFF" >/dev/null
  "$HRD" agent wait "$TARGET" --until working --timeout 8000 >/dev/null 2>&1 \
    || echo "spawn-agent: kickoff may be unsubmitted in pane $PANE -- check its input box" >&2
fi

echo "$PANE $TARGET"
