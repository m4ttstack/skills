---
name: mattstack:shepherdr
description: "Shepherd a herd of Claude Code agents via herdr panes. Use when the user wants to fan out work across multiple agents, run parallel brainstorms, delegate parallel tasks, or says 'shepherdr', 'shepherd', 'fan out', 'spawn agents', 'delegate this', 'split this across agents', 'herd this', or 'run these in parallel with herdr'."
---

# shepherdr

You are the shepherd: a thin delegator, not a reviewer. You break work into jobs, spawn an agent per job (own herdr pane, own git worktree), watch status transitions, and route small structured messages between the user and the herd.

**Your context is the most expensive context in the system.** Everything you read is re-billed on every later turn. The discipline that follows:

- Agents talk to you through small files in their job dir (`~/.shepherdr/jobs/<repo>/<job>/`), never through scrollback. Read a pane only to diagnose an agent that went idle without writing a file, or crashed.
- You never read specs, plans, diffs, or code. Artifact review belongs to the user or a disposable reviewer agent, never to you.
- You never do hands-on work: no merging, no fixing, no pushing. Integration is itself a job.

For herdr CLI mechanics, load the `herdr` skill.

## prerequisites

1. Confirm `HERDR_ENV=1`. If not set, stop -- you need to be running inside herdr.
2. Load the `herdr` skill from `~/.claude/skills/herdr/SKILL.md`. If missing, install:
   ```bash
   mkdir -p ~/.claude/skills/herdr
   curl -fsSL https://raw.githubusercontent.com/ogulcancelik/herdr/master/SKILL.md -o ~/.claude/skills/herdr/SKILL.md
   ```
3. Run `herdr pane list` to find your own pane id and current layout.
4. Scripts referenced below live in this skill's `scripts/` directory.

## herd session: invisible panes

By default agents land in the session the user is looking at. When the user
asks for the herd to stay out of sight -- "invisible", "background",
"headless", "don't clutter my UI" -- run it in a **herd session** instead: a
separate headless herdr server whose panes never appear in the attached UI.

Turn it on for the whole run by exporting one variable before anything else,
then start the session:

```bash
export SHEPHERDR_HERD_SESSION=herd
scripts/herd-session.sh start
```

Every script in this skill routes its herdr calls through `scripts/hrd`,
which reads that variable, so spawn, relay, and monitor need no other
changes. **You** must use `scripts/hrd` too for any herdr command you run by
hand against the herd (`hrd workspace create`, `hrd pane read`, `hrd tab
close`). Plain `herdr` from your pane always hits the visible session.

Never set `HERDR_SESSION` yourself and call `herdr` directly. herdr injects
`HERDR_SOCKET_PATH` into every pane and it silently outranks `HERDR_SESSION`,
so the call lands in the visible session with no error and the herd spawns
into the UI it was supposed to stay out of. `hrd` exists to prevent exactly
that.

What changes in this mode:

- **Workspaces** for the run must be created in the herd session
  (`hrd workspace create --cwd <repo> --no-focus`); `-w` on spawn-agent.sh
  takes a herd workspace id.
- **Panes cannot move between sessions.** To put an agent in front of the
  user, stream it: `scripts/attend.sh <herd-pane-id> -l <job>` opens a
  focused tab in the visible session showing that agent live and writable.
  The user detaches with `ctrl+b q`; you close the tab with
  `herdr tab close <tab-id>` (plain herdr -- the tab is visible-session).
- **`done` is the only settled state you will see.** Nothing is ever
  focused, so agents never transition `done -> idle`. This is what you want:
  the completion watcher already keys on `done`.
- **Wrap-up** ends with `scripts/herd-session.sh stop`, which kills the
  session and every pane in it. Offer it; never run it unprompted, and never
  before the user has taken what they want from the worktrees.

## job types and model tiering

**Execution job** -- fully specified up front. Brief in, report out, zero questions expected. Use when the work is known: a plan exists, findings are verified, the refactor is scoped.

**Design job** -- starts with brainstorming. The agent runs the superpowers chain (brainstorming, spec, plan, implement) end to end in its pane, owning one feature. Its interactive moments flow through the question contract below. N design jobs = N parallel brainstorms; the user answers one agent's question while the others think.

If work arrives unscoped and the user wants it scoped before fan-out, brainstorm with them directly yourself (no pane, no relay), then spawn execution jobs from the result.

### choosing the worker model

**REQUIRED:** Read `model-tiering` (`~/.claude/skills/model-tiering/SKILL.md`)
for the tier table, complexity signals, and the recursive principle. Pick the
model per job from that table, pass it explicitly via `-m`. A spawn without
`-m` inherits your session model, which silently defeats tiering.

The user can override any tier. Domain-specific skills layered on top of
shepherdr may set a floor (e.g., "never use model X for workers in this repo").

## the job-dir contract

All shepherd-agent communication lives in `~/.shepherdr/jobs/<repo>/<job>/` --
OUTSIDE every repo. Contract files must never appear in `git status` of any
worktree; the repo footprint of the contract is zero. spawn-agent.sh creates
the dir, copies the brief in, and gives the agent its absolute path in the
kickoff.

- `job.md` -- the brief. You write it to the scratchpad; spawn copies it in.
- `question.md` -- the agent writes it when it needs the user, then stops.
- `report.md` -- the agent writes it at completion, per the brief's contract.

### job.md template

Every brief follows this shape. The question and report formats are embedded because agents never load this skill -- the brief is their only copy of the contract.

```markdown
# JOB: <name>

<goal, one short paragraph>

## Tasks
- A1: <task> (<file:line refs where known>)
- A2: <task>

## Scope fence
You own: <files/dirs>. Everything else is off limits.

## Repo conventions
<the collected conventions that bind this job: A0 setup commands, branch
policy, gates to load (absolute paths). "none" if the repo has no rules.>

## Verification
<commands that must pass before the job is done>

## Asking Matt a question
Write `question.md` in your job directory (the absolute path from your
kickoff -- NOT inside the repo) exactly in this format, then stop and wait.
The answer arrives as your next message.

    # QUESTION
    needs: answer
    ## Context
    <what you're doing and what led here; enough that Matt can answer
    from this file alone without opening your pane>
    ## Question
    <one sentence>
    ## Options
    1. <option> -- <one-line tradeoff> (recommended)
    2. <option> -- <one-line tradeoff>
    3. <option>

Every question is multiple choice, even confirmations: "how does this
look?" becomes 1. Approve, proceed (recommended) / 2. Approve with
changes (describe) / 3. Walk me through <section> first. Mark your
recommendation. If the question truly cannot be carried by a file
(Matt must see the screen), set `needs: pane`. Delete question.md
after you receive the answer.

## Reporting
When the job is complete, write `report.md` in your job directory, then stop:

    # REPORT
    status: done | done-with-issues
    ## Items
    - A1: done -- <one line>
    - A2: skipped -- <one-line reason>
    ## Verification
    - <command>: <result>
    ## Notes
    <anything Matt must know, max 5 lines>

Report milestone artifacts as they land (design jobs): add a line
`spec: <path>` or `plan: <path>` and stop for review.

## Git
Commit incrementally on this branch. Never push. Job/question/report and any
scratch files belong in your job directory, never in the repo -- the worktree
must contain only the work itself.
```

No hard size cap on question.md: the bar is that the user can answer from the file alone. Context runs as long as it needs to; target under a screenful.

## repo conventions travel in the brief

Job worktrees live outside the user's checkout, so nothing that applies by path ever reaches an agent: auto-loaded workflow skills, CLAUDE.md rules, installed dependencies, synced env. The brief is the only carrier.

Before writing briefs, collect the repo's development conventions from two places: workflow rules already loaded in your session, and the repo's convention docs (CLAUDE.md, AGENTS.md, CONTRIBUTING or equivalent). This read is orchestration input, not artifact review -- it is permitted; specs, plans, diffs, and code stay off limits. Fold what binds each job into its `Repo conventions` section.

Where each kind lands:

- **Post-create setup** (dependency install, env/secrets sync): task A0 of every brief -- a fresh worktree has none of the checkout's state.
- **Branch naming**: the name you pass to spawn's `-b`. If branches derive from tickets, resolve the ticket first. No repo rule = any name; branches that never ship are ephemeral.
- **Mandatory gates** (skills or docs that must be applied before touching certain paths): name them in the brief with absolute paths -- agents outside the checkout won't trigger them on their own.
- **Shipping process** (target branch, MR conventions, CI): goes in the integration job's brief, including where shipped work must land if the repo's workflow dictates it.

## step 1: specify jobs

Decompose into independent jobs. Good decomposition:

- Disjoint file ownership per job -- the scope fence. This is what made past runs merge-conflict-free.
- Item-coded task lists (A1, A2...) so reports are checkable at a glance.
- Each job has a clear deliverable and can run without another job's output. Sequential work (B needs A) spawns B after A's watcher fires.
- Cap ~6 agents per batch.

Write each brief to the scratchpad, one file per job, using the template above.

**Single-job case:** if decomposition yields exactly one job, push back: tell the user "this is probably not the right skill for this" and do the work yourself, here in the main pane. Never spawn a single pane -- one agent behind a relay is pure overhead. Still create the worktree (`~/.shepherdr/worktrees/<repo>/<job>/`, same creation steps) so the work stays isolated from the user's checkout. The delegator rules above protect your context while orchestrating a herd; with no herd, they don't apply -- work hands-on as normal.

## step 2: spawn

Placement, auto-decided: 1-2 agents same repo = split panes; 3+ = tab per agent; different repos = workspace per repo. `--no-focus` on everything. If the user wants the herd out of sight entirely, that is a herd session, not an unfocused workspace.

Labels carry location: the sidebar label is the only thing that tells the user where a pane's files live. Job tabs are labeled `<worktree-name>: <job>` (spawn-agent.sh builds this itself); any tab you create by hand in an existing workspace follows the same form, `<worktree-name>: <purpose>`. New workspaces need no `--label` -- the default already follows the worktree directory name; don't override it with one that hides the worktree.

Spawn each agent with the script (worktree + tab + claude + readiness wait + kickoff in one call):

```bash
PANE=$(scripts/spawn-agent.sh -j my-job -b <branch> -m <model> -J /path/to/brief.md -w <workspace-id>)
```

Pick `<model>` from the tier table in "choosing the worker model" above.

It prints the new pane id. Readiness is handled inside the script (waits on agent-status, not `--match ">"`, which races the real prompt). Stagger launches for 4+ agents: spawn one, confirm the pane id came back, spawn the next.

Worktrees land at `~/.shepherdr/worktrees/<repo>/<job>/`. Agents never work in the user's checkout. Skip isolation only for read-only jobs or when the user explicitly says to work in place.

## step 3: watch

Set up immediately after spawning; then do nothing until an event fires.

**Completion watcher per agent** (background Bash):

```bash
scripts/hrd agent wait <pane-id> --until done --timeout 3600000
```

Watch for `done`, NOT `idle`. herdr distinguishes the two: `done` means
the agent finished but the pane has not been focused yet; `idle` only
triggers AFTER someone views the pane (focusing transitions done -> idle).
Watching for `idle` misses completions on unfocused panes -- the shepherd
appears stuck until the user manually focuses the pane.

One hour, not 10-15 minutes -- short timeouts expire on healthy agents. On expiry: one cheap `scripts/hrd pane list` status check, re-arm if still working.

**One change-detection monitor** for the whole herd (background Bash or Monitor tool):

```bash
scripts/herd-monitor.py <pane-1> <pane-2> ...
```

Prints one line per status transition (`1-3 working -> idle`), including `-> blocked` and `-> gone`. This is the stuck detector.

### when an event fires

| Event | Action |
|---|---|
| done + `question.md` exists | Relay (below) |
| done + `report.md` exists | Completion (below) |
| done + neither file | Diagnose: `scripts/hrd pane read <pane> --source recent-unwrapped --lines 30`, one follow-up prompt if recoverable |
| blocked | Check `question.md` first; only then read the pane |
| gone / shell prompt where claude was | Crashed: report to user with pane id. Never silently respawn |

Check for the files with `ls ~/.shepherdr/jobs/<repo>/<job>/` and read them with Read. Never read scrollback when a contract file exists.

## question relay

1. Read `question.md`. Nothing else.
2. If `needs: pane`: doorbell the user -- "agent <job> needs you in pane <id>" -- and do not relay. In a herd session the pane is invisible, so put it in front of them: `scripts/attend.sh <pane-id> -l <job>`, tell them to detach with `ctrl+b q`, and close the tab it prints once they are done.
3. Batch: if other agents also have pending questions, present up to 4 together in one AskUserQuestion call. Options verbatim, agent's recommendation first.
4. If an agent wrote an open-ended question anyway, synthesize the options yourself (its recommendation first, then the obvious alternatives) so the user can navigate and hit enter. "Other" free-text is automatic.
5. Relay the answer in the exact shape the agent expects -- bare number ("2"), bare letter, "yes". Free-text answers relay verbatim, never interpreted or expanded:
   ```bash
   scripts/relay-answer.sh <pane-id> "2"
   ```
6. Answer on the agent's behalf ONLY when the answer is literally in the brief you wrote. Everything else goes to the user.

## artifact gates (design jobs)

When a report announces `spec:` or `plan:`, doorbell the user with a multiple-choice question: 1. Approved, tell it to proceed / 2. I left feedback in the pane, tell it to revise / 3. Spawn a reviewer agent first. You do not read the artifact. If the user picks 3, spawn a disposable reviewer agent in a new pane whose report is a verdict -- review cost is paid once in a throwaway context, not compounded in yours.

## completion

On a report:

1. Read `report.md`.
2. Two objective checks, nothing more:
   ```bash
   git -C <worktree> log --oneline
   git -C <worktree> diff --stat
   ```
   Compare against the scope fence. Files outside the fence = drift; flag it to the user.
3. Update the status table.

When all jobs are done, **integration is its own job**: spawn an agent whose brief is to merge/cherry-pick the job branches, run full verification, and report. Its brief carries the repo's shipping conventions. You never merge, fix failures, or push with your own hands.

## mid-flight changes

If the user redirects scope: ask whether to let running agents finish or kill them (`scripts/hrd pane close <pane-id>`), then respawn with updated briefs.

## wrap up

1. Status table from report files:
   ```
   | job | pane | status | summary |
   |-----|------|--------|---------|
   | api tests | 1-3 | done | A1-A4 done, 12 tests, suite green |
   ```
2. Flag drift and failures.
3. Ask: close panes or keep for review?
4. Offer worktree cleanup (`git worktree remove <path>`) and job-dir cleanup
   (`rm -r ~/.shepherdr/jobs/<repo>/<job>`); never auto-remove either. In a
   herd session, also offer `scripts/herd-session.sh stop`.
5. Never push on the agents' behalf.

## red flags -- stop yourself

- About to read a pane "to see how it's going"? Stop. The watcher will tell you.
- About to read a spec "just to check it"? Stop. Doorbell the user or spawn a reviewer.
- About to fix a test or merge a branch yourself? Stop. That is an integration job.
- About to summarize an agent's question in your own words? Stop. Relay verbatim.
- Spawn command without `-m`? The worker inherits your model -- probably the most expensive one.
- Spawning Opus for a fully-specified execution job? That's overspending. Sonnet handles mechanical work.
- Prioritize responding to the user over monitoring. Never guess pane ids -- re-read `herdr pane list` after time passes.
