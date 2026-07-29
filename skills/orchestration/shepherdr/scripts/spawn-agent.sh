#!/usr/bin/env bash
# Spawn one shepherdr agent: worktree + herdr tab + claude + kickoff prompt.
#
# Usage:
#   spawn-agent.sh -j <job-name> (-b <branch> | -d <existing-dir>) -J <brief.md>
#                  -w <workspace-id> [-r <repo-root>] [-k <kickoff-text>] [-m <model>]
#
# With -b: creates the worktree at ~/.shepherdr/worktrees/<repo>/<job-name>.
# With -d: uses the existing directory as-is (no git worktree add); any branch
# must already be provisioned there. -m launches claude with --model <model>.
# Copies the brief to the job dir ~/.shepherdr/jobs/<repo>/<job-name>/job.md
# (contract files never live inside the repo), opens a --no-focus tab labeled
# "<worktree>: <job>" in the given workspace, launches claude, waits for
# readiness, sends the kickoff, and confirms it submitted (nudging with Enter
# if paste detection swallowed it).
# Prints the new pane id on stdout; everything else goes to stderr.
#
# With SHEPHERDR_HERD_SESSION set, the tab is created in that invisible herd
# session instead of the visible one; -w must then be a workspace id from
# that session. Nothing else about the call changes.
set -euo pipefail

# All herdr traffic goes through the shim, which is what makes the visible /
# invisible switch a single env var. See scripts/hrd.
HRD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hrd"

usage() { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

REPO_ROOT=""
KICKOFF=""
BRANCH=""
DIR=""
MODEL=""
while getopts "j:b:J:w:r:k:d:m:" opt; do
  case "$opt" in
    j) JOB="$OPTARG" ;;
    b) BRANCH="$OPTARG" ;;
    J) JOB_MD="$OPTARG" ;;
    w) WORKSPACE="$OPTARG" ;;
    r) REPO_ROOT="$OPTARG" ;;
    k) KICKOFF="$OPTARG" ;;
    d) DIR="$OPTARG" ;;
    m) MODEL="$OPTARG" ;;
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
"$HRD" pane run "$PANE" "claude${MODEL:+ --model '$MODEL'}"

# Readiness: wait for herdr to detect the agent and see it idle. Matching
# --match ">" races the real prompt char and produces dead kickoff prompts.
# `done` is accepted too: it is the same settled state as idle for a pane
# nobody has looked at, and in a herd session nobody ever looks.
if ! "$HRD" agent wait "$PANE" --until idle --until done --timeout 45000 >/dev/null 2>&1; then
  echo "spawn-agent: agent-status wait timed out for $PANE; falling back to prompt match" >&2
  "$HRD" pane wait-output "$PANE" --match "❯" --timeout 15000 >/dev/null
fi

if [ -z "$KICKOFF" ]; then
  KICKOFF="Your job directory is $JOB_DIR -- it is outside the repo, and all job/question/report and scratch files belong there, NEVER in the repo or worktree. Read $JOB_DIR/job.md and complete the entire job it describes. Work only inside this worktree and stay within the brief's scope fence. The brief's verification commands must pass. Whenever you need input from Matt, write $JOB_DIR/question.md in the multiple-choice format the brief shows, then stop and wait; the answer arrives as your next message. Even yes/no confirmations become numbered options. When the job is complete, write $JOB_DIR/report.md per the brief, then stop. Commit incrementally on this branch; never push. The worktree must contain only the work itself."
fi
"$HRD" pane run "$PANE" "$KICKOFF"

# Claude's TUI can treat fast text+Enter as a paste, leaving the kickoff
# sitting unsubmitted in the input box. Confirm the agent actually started
# working; nudge with a bare Enter if it did not (harmless when it did).
if ! "$HRD" agent wait "$PANE" --until working --timeout 8000 >/dev/null 2>&1; then
  "$HRD" pane send-keys "$PANE" Enter
  "$HRD" agent wait "$PANE" --until working --timeout 8000 >/dev/null 2>&1 \
    || echo "spawn-agent: kickoff may be unsubmitted in pane $PANE -- check its input box" >&2
fi

echo "$PANE"
