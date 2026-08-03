# shepherdr v2: thin delegator

Revision of `skills/orchestration/shepherdr/SKILL.md`. The shepherd stops being an opinionated reviewer and becomes a thin delegator: it routes small structured messages, watches status transitions, and never reads prose it doesn't have to. The interactive back-and-forth with sub-agents stays (it's load-bearing for parallel brainstorming), but every hop gets ~10x cheaper.

## Problem

Evidence from the 2026-07-01 runs (3 shepherd sessions driving 19 sub-agents across three separate repos):

- Completion pane reads were cheap (~2.5-3KB each, 25-30% of tool-result bytes). Not the villain.
- The brainstorm-behind-relay was expensive: 16 relayed messages, 7 question round-trips, ~15 pane reads just to see question text, plus scrollback archaeology when reports scrolled away.
- Monitoring scaffolding was re-derived from scratch 3x in one evening (including a bash-3.2 failure and Python rewrite).
- A readiness race (`herdr wait output --match ">"` vs the real `❯` prompt) caused 3-4 dead kickoff prompts.
- Watcher timeout guesswork: 10-15 min timeouts expired on healthy agents.
- Commit policy was inconsistent; where agents didn't commit, the shepherd did hands-on integration itself (merged, fixed 27 tsc errors, pushed).
- Everything the shepherd reads persists in its context and is re-billed every subsequent turn, so artifact reads (full specs) are the one cost that compounds.

## Core principles

1. The shepherd's context is the most expensive context in the system. It never reads pane scrollback except to diagnose a stuck/crashed agent, never reads specs/plans/artifacts, never reviews prose.
2. Fidelity lives in artifacts (briefs, specs, plans), not in shepherd oversight. Superpowers still runs, in the panes, with cheap structured relay for its interactive moments.
3. All communication between agent and shepherd flows through small structured files in the worktree, not scrollback.
4. Everything becomes multiple choice at the relay boundary, so the user can navigate and hit enter.

## Two job types, one monitoring spine

**Execution jobs** (fully specified up front): brief in, report out, zero relay expected. This is the shape of the successful fix waves.

**Design jobs** (start with brainstorming): the agent runs the superpowers chain (brainstorming, spec, writing-plans, execution) in its own pane, end to end, owning its feature in its worktree. Interactive moments flow through the question contract. N design jobs in parallel = N simultaneous brainstorms, pipelined across the user's answer gaps.

A single herd can mix both types. Cap stays at ~6 agents per batch.

## File contracts: `.shepherdr/` in each worktree

All shepherd-agent communication lives in `<worktree>/.shepherdr/`. Agents never commit this directory.

### `job.md` (shepherd writes, before spawn)

The brief. Goal, item-coded task list (A1, A2, ...) with file:line refs where known, scope fence (which files/dirs this job owns; everything else is off limits), verification commands, definition of done. Item codes are what make completion reports checkable at a glance.

### `question.md` (agent writes, then goes idle)

Written whenever the agent needs the user, then the agent goes idle so the status watcher fires. Format:

```markdown
# QUESTION
needs: answer | pane
## Context
What I'm working on and what led to this. As long as it needs to be for the
user to answer from this file alone; target under a screenful.
## Question
One sentence.
## Options
1. <option> ... <one-line tradeoff> (recommended)
2. <option> ... <one-line tradeoff>
3. <option> ...
```

Rules:
- No hard line cap. The bar: the user can answer from the file alone, without opening the pane.
- ALWAYS multiple choice, even confirmations. "How does that sound?" becomes: 1. Approve, proceed (recommended) / 2. Approve with changes (describe) / 3. Walk me through <specific section> first. The kickoff prompt instructs agents to do this translation themselves.
- Recommendation always marked, listed first.
- `needs: pane` is the doorbell escape hatch: the question genuinely can't be carried by a file (user must see a mockup, a diff, a live TUI). The shepherd then just points the user at the pane and does not relay.
- Agent deletes or overwrites `question.md` after receiving the answer, so a stale file is never mistaken for a pending one.

### `report.md` (agent writes at completion, per the kickoff contract, not as a follow-up)

```markdown
# REPORT
status: done | done-with-issues
## Items
- A1: done ... <one line>
- A2: skipped ... <one-line reason>
## Verification
- <command>: <result, e.g. 319/319>
## Notes
Anything the user must know. <= 5 lines.
```

For design jobs, milestone artifacts get reported here too: `spec: <path>` when the spec is ready for review, `plan: <path>` likewise.

## Question relay (shepherd side)

1. Watcher fires on an idle/blocked transition. Shepherd checks `question.md` FIRST; only reads the pane if there's no question file and no report file (diagnosis case).
2. Pending questions are batched: up to 4 per AskUserQuestion call, options preserved verbatim, agent's recommendation listed first.
3. If an agent wrote an open-ended question anyway, the shepherd synthesizes the options itself (agent's recommendation first, plus the obvious alternatives) before presenting. The user always gets a navigable list; "Other" free-text is automatic.
4. Answers relay back in the exact format the agent expects: bare number ("2"), bare letter, "yes"/"no". Free-text "Other" answers relay verbatim, unedited. Never interpreted, summarized, or expanded.
5. Relay mechanics: always `herdr pane send-keys <pane> ctrl+c` to clear any auto-drafted buffer, then `herdr pane run <pane> "<answer>"`.
6. The shepherd answers on the agent's behalf ONLY when the answer is literally in the job brief it wrote. Everything else goes to the user.

## Artifact review (spec/plan gates in design jobs)

The shepherd NEVER reads specs or plans. When `report.md` announces a spec, the shepherd doorbells the user: path + pane id, presented as a multiple-choice question (1. Approved, tell it to proceed / 2. I left feedback in the pane, tell it to revise / 3. Spawn a reviewer agent first). If the user wants a machine pass, the shepherd spawns a disposable reviewer agent in a new pane whose report is a verdict, so review cost is paid once in a throwaway context instead of compounding in the shepherd's.

## Monitoring spine

- **Per-agent completion watchers**: `herdr wait agent-status <pane> --status idle --timeout 3600000` via background Bash. One hour, not 10-15 minutes; timeouts caused false alarms. On expiry: one cheap `herdr pane list` status check, re-arm if still working.
- **One persistent change-detection Monitor** running the shipped Python script (below): polls `herdr pane list` every 30s, emits only status transitions. This is the stuck/blocked detector.
- **No routine pane reads.** Pane reads only when: no question.md and no report.md after an idle transition (diagnosis), or a crash (shell prompt where claude should be). Crash = report to user with pane id; never silently respawn.

## Shipped scaffolding (new `scripts/` dir in the skill)

Re-derived-per-session code becomes files the shepherd runs:

- `scripts/herd-monitor.py`: the change-detection poller. Python, not bash (macOS bash 3.2 has no associative arrays and broke on the night of evidence). Takes pane ids, prints one line per status transition.
- `scripts/spawn-agent.sh`: worktree add + tab/pane create (`--no-focus`) + cd + launch claude + readiness wait + kickoff prompt delivery. Readiness fix baked in: wait on `herdr wait agent-status <pane> --status idle` (or match `❯`), never `--match ">"`.
- `scripts/relay-answer.sh`: ctrl+c then pane run, quoted safely.

SKILL.md references these by path; the shepherd uses them instead of writing its own.

## Commit and integration policy

- Agents commit incrementally on their own job branch (aligned with the user's incremental-commits rule; reverses v1's "do not tell them to commit"). Never push. Never commit `.shepherdr/`.
- Integration is its own job in its own pane: merge/cherry-pick the job branches, run full verification, write a report. The shepherd never merges, fixes, or pushes with its own hands.
- Shepherd-side objective checks on completion are limited to: `git -C <worktree> log --oneline` and `git -C <worktree> diff --stat` compared against the job's scope fence. Two lines to detect drift; no prose review.

## Deleted from v1

- The entire "artifact review gates" section (shepherd reads spec, critiques, correction loop, summarizes).
- The "your role during superpowers: quality gate" framing and interpreted relay.
- Default 50-line pane reads on every notification.
- "Do not tell them to commit."
- Shepherd answering "trivial or obvious" questions beyond what the brief states.

## Kept from v1

- Worktree isolation exactly as is (`~/.shepherdr/worktrees/<repo>/<job>/`, skip only for read-only work or explicit user request).
- Placement logic (panes vs tabs vs workspaces), `--no-focus` everywhere.
- ~6 agent cap per batch; stagger launches for 4+.
- Never guess pane ids; re-read `herdr pane list` after time passes.
- Wrap-up: status table (now sourced from report.md files), conflict flagging, close/keep panes question, worktree cleanup offer, no auto-remove.
- herdr skill prerequisite and install fallback.

## Kickoff prompt template (goes in SKILL.md)

Every kickoff prompt contains, in order: (1) read `.shepherdr/job.md` and complete it; (2) scope fence restated in one line; (3) verification commands that must pass; (4) question contract: write `.shepherdr/question.md` in the multiple-choice format and go idle whenever you need Matt; even yes/no confirmations become numbered options; (5) report contract: write `.shepherdr/report.md` before going idle when done; (6) commit policy: commit incrementally on this branch, never push, never commit `.shepherdr/`.

## Out of scope

- Changes to the herdr skill/CLI itself (the e2e prompt-leak bug is herdr's problem, noted in memory already).
- Multi-repo herds beyond what v1's placement rules already cover.
- Any automation of spec approval; the user is always the approver for design jobs.
