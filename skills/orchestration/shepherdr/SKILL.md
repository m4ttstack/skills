---
name: mattstack:shepherdr
description: "Shepherd a herd of Claude Code agents via herdr panes. Use when the user wants to fan out work across multiple agents, run parallel brainstorms, delegate parallel tasks, or says 'shepherdr', 'shepherd', 'fan out', 'spawn agents', 'delegate this', 'split this across agents', 'herd this', 'run these in parallel with herdr', 'spread this across my accounts', or asks for multi-account or cswap-aware fan-out."
---

# shepherdr

You are the shepherd: a thin delegator, not a reviewer. You break work into jobs, spawn an agent per job (own herdr pane, own git worktree), watch status transitions, and route small structured messages between the user and the herd.

**Your context is the most expensive context in the system.** Everything you read is re-billed on every later turn. The discipline that follows:

- Agents talk to you through small files in their job dir (`~/.shepherdr/jobs/<repo>/<job>/`), never through scrollback. Read a pane only to diagnose an agent that went idle without writing a file, or crashed.
- You never read specs, plans, diffs, or code. Artifact review belongs to the user or a disposable reviewer agent, never to you.
- You never do hands-on work: no merging, no fixing, no pushing. Integration is itself a job.

For herdr CLI mechanics, load the `herdr` skill.

## when not to herd

A small, fully specified execution fan-out with no expected questions, no
need for account spreading, and no need to watch or steer live belongs on
the Agent tool (subagents with worktree isolation), not panes. The herd
earns its keep through account distribution, mid-flight interaction
(question relay, artifact gates), live visibility, and crash-survivable
jobs. If none of those apply, say so and dispatch subagents instead.

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

When the user asks for the herd to stay out of sight ("invisible",
"background", "headless"), read `references/herd-session.md` in this
skill's directory and follow it. Do not load it otherwise.

## job types and model tiering

**Execution job** -- fully specified up front. Brief in, report out, zero questions expected. Use when the work is known: a plan exists, findings are verified, the refactor is scoped.

**Design job** -- starts with brainstorming. The agent runs the superpowers chain (brainstorming, spec, plan, implement) end to end in its pane, owning one feature. Its interactive moments flow through the question contract below. N design jobs = N parallel brainstorms; the user answers one agent's question while the others think.

If work arrives unscoped and the user wants it scoped before fan-out, brainstorm with them directly yourself (no pane, no relay), then spawn execution jobs from the result.

### choosing the worker model

**REQUIRED:** Read `mattstack:model-tiering` (`~/.claude/skills/mattstack:model-tiering/SKILL.md`)
for the tier table, complexity signals, and the recursive principle. Pick the
model per job from that table, pass it explicitly via `-m`. A spawn without
`-m` inherits your session model, which silently defeats tiering.

The user can override any tier. Domain-specific skills layered on top of
shepherdr may set a floor (e.g., "never use model X for workers in this repo").

## accounts (cswap)

At fan-out, if `cswap` is installed and `cswap list --json` shows two or
more accounts, ask ONE structured question (AskUserQuestion, single
choice) before spawning anything: how should this herd use accounts?

1. Smart distribute across all accounts (recommended)
2. Smart distribute across a subset -- follow-up multi-select of accounts
3. Single account -- follow-up single-select

Show each account's email/alias and current headroom in the option
descriptions so the choice is informed at a glance. The selection is the
session pool: record it in the status table and never spawn or respawn
outside it without explicit approval. No cswap or a single account: skip
all of this; workers launch as plain claude exactly as before.

Before each spawn in a smart-distribute herd, run the picker and pass the
result to spawn-agent.sh via `-a`:

```bash
ACCT=$(scripts/pick-account.py --pool 2,3 --model <model> --assigned <accounts-already-assigned>)
```

`--assigned` lists the account of every pane already spawned this run,
one entry per pane. The picker excludes accounts near their limits and
answers with the healthiest account for that worker's model; it exits
nonzero when no pool account qualifies -- surface that to the user as a
structured question, never spawn anyway.

If a worker stalls on a rate limit mid-job (the diagnose read shows a
limit banner): in smart-distribute mode with a qualifying account left in
the pool, respawn automatically -- close the pane, re-run the picker,
respawn with the SAME job dir and worktree, and prefix the kickoff with:
"A previous agent started this job and hit a rate limit. Check git log
and the job directory, then continue and complete the brief." Announce
the respawn to the user afterward. In single-account mode or with the
pool exhausted, ask instead: 1. wait for reset (show the countdown from
cswap list --json), 2. switch to an out-of-pool account, 3. abandon.

Note: cswap sessions share settings and skills but not plugin caches.
Workers get everything through their briefs, so do not chase phantom
missing-plugin issues in worker panes.

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

Copy `references/job-template.md` (in this skill's directory) verbatim
for every brief and fill the slots. Do not retype it from memory: the
question and report formats it embeds are the workers' only copy of the
contract.

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
OUT=$(scripts/spawn-agent.sh -j my-job -b <branch> -m <model> -J /path/to/brief.md -w <workspace-id> [-a <account>])
PANE=${OUT%% *}; TARGET=${OUT##* }
```

Pick `<model>` from the tier table in "choosing the worker model" above,
and `<account>` from the picker when the herd is account-distributed.

It prints the pane id and the agent's name; use the name (`$TARGET`) for
every later agent command. Readiness and kickoff submission are native
(`agent wait`, `agent prompt`); a spawn that cannot reach a ready agent
fails loudly instead of guessing. Stagger launches for 4+ agents: spawn
one, confirm it returned, spawn the next.

Worktrees land at `~/.shepherdr/worktrees/<repo>/<job>/`. Agents never work in the user's checkout. Skip isolation only for read-only jobs or when the user explicitly says to work in place.

## step 3: watch

Set up immediately after spawning; then do nothing until an event fires.

**Completion watcher per agent** (background Bash):

```bash
scripts/hrd agent wait <target> --until done --until idle --until blocked --timeout 3600000
```

One wait covers settled work (`done`, and `idle` -- herd-session panes
settle at idle, and wait matching is exact with no implicit fallback, so
both must be listed) and a recognized question or approval UI
(`blocked`), so blocked is event-driven. A wait that errors because its
pane vanished is the `gone` signal.

One hour, not 10-15 minutes -- short timeouts expire on healthy agents.
On expiry: one cheap `scripts/hrd pane list` status check, re-arm if
still working.

**Safety-net monitor** for the whole herd (background Bash or Monitor tool):

```bash
scripts/herd-monitor.py <pane-1> <pane-2> ...
```

The per-agent waits are primary; the monitor is a belt-and-suspenders
poller that catches anything a wait misses and reports `-> gone` when a
pane disappears.

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
3. Doorbell before relaying: `herdr notification show "<job> needs you" --body "<one-line question>" --sound request` (plain herdr, never the hrd shim -- notifications target the attached UI even when the herd is invisible). On full-herd completion at wrap-up, send one with `--sound done`.
4. Batch: if other agents also have pending questions, present up to 4 together in one AskUserQuestion call. Options verbatim, agent's recommendation first.
5. If an agent wrote an open-ended question anyway, synthesize the options yourself (its recommendation first, then the obvious alternatives) so the user can navigate and hit enter. "Other" free-text is automatic.
6. Relay the answer in the exact shape the agent expects -- bare number ("2"), bare letter, "yes". Free-text answers relay verbatim, never interpreted or expanded:
   ```bash
   scripts/relay-answer.sh $TARGET "2"
   ```
7. Answer on the agent's behalf ONLY when the answer is literally in the brief you wrote. Everything else goes to the user.

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
   | job | pane | account | status | summary |
   |-----|------|---------|--------|---------|
   | api tests | 1-3 | 2 | done | A1-A4 done, 12 tests, suite green |
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
- Target agents by job name; if a name fails to resolve, re-read herdr agent list -- never guess.
- cswap is installed with 2+ accounts and you are about to spawn without having asked the account-mode question? Stop. One structured question first.
- About to respawn a rate-limited job under an account outside the session pool? Stop. That needs explicit approval.
