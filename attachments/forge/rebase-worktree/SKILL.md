---
name: rebase-worktree
disable-model-invocation: true
description: "Use when one worktree's feature branch has fallen behind the default branch -- 'rebase this worktree', a stale MR branch -- or as the per-branch step of sync-open-mrs. Not for resolving conflicts on its own or moving uncommitted work."
allowed-tools:
  - Bash(git -C * fetch:*)
  - Bash(git -C * status:*)
  - Bash(git -C * log:*)
  - Bash(git -C * symbolic-ref:*)
  - Bash(git -C * remote set-head:*)
  - Bash(gh pr list:*)
  - Bash(gh pr view:*)
  - Bash(gh repo view:*)
type: pipeline-step
slots: {}
---

# rebase-worktree

Bring one worktree's branch current with the default branch: the
`branch_sync` tool first, the manual rebase only where `branch_sync` did
not run. This never guesses -- it refuses on a dirty tree, refuses a stack
member, and hands conflicts back to a human.

## Preconditions

Check these before anything mutates, and report before touching history:

- **Clean tree.** `git -C <worktree> status --porcelain` must be empty.
  Dirty: one sentence listing the uncommitted paths, then, when this
  conversation holds a run's `runDb`, the `run_field_set` tool with that
  `runDb`, `key` `gate`, `value` `clarify`, `stage`
  `<run.current_stage>`, and run gate-protocol's Runs integration with
  kind `clarify` and these questions: **I committed them, retry** /
  **Abort**; **Hold**, recorded after with the `run_decision` tool:
  `contract` `gate@1`, `scope` `clarify`, `selection`
  `{"tree":"retry|abort"}`, `decidedBy` `<the answer's by>`.

{{include:spawned-no-run-guard}}

Never `git stash` and proceed: moving someone's uncommitted work is not
this skill's call. The STOP table under the push gate binds this form
too.
- **Upstream set.** `git -C <worktree> status -sb` prints the branch line
  first; no `...origin/<branch>` tracking ref there means no upstream --
  stop and report, there's nothing to rebase onto.
- **Discover the default branch.** `git -C <worktree> symbolic-ref
  refs/remotes/origin/HEAD`. If that's unset: GitHub: `gh repo view
  --json defaultBranchRef`; GitLab: `git -C <worktree> remote set-head
  origin --auto` (it sets the local ref and pushes nothing), then read the
  symbolic-ref again. An MR's `targetBranch` is where that MR merges, not
  the default branch: never take the default from it. Never hardcode a
  branch name.

## Fast path: branch_sync

With the preconditions clean, one tool call does the fetch, the stack
check, the rebase, and the push, and says why when it will not. Note the
head with `git -C <worktree> log -1 --oneline`, then call the
`branch_sync` tool with `tree` = the worktree's absolute path.

The result decides, and nothing else does:

| result | carries | next |
|---|---|---|
| `status: "synced"` | the branch's new state | Synced: `branch_sync` rebased (or found the branch current) and pushed with force-with-lease. Report the move as in **After a clean rebase**; the push already happened, so no push gate. |
| `status: "conflict"` | the bundle (`unresolvedFiles`, `backupBranch`, `state: mid-rebase`) | The rebase is paused in the worktree. Go to **On conflict** with `unresolvedFiles` as the files. |
| error: a stack refusal | the stack or its MRs, the stack tool, a hint | REFUSE: report the error text, say the hint, name the stack tool to run. The run ends here; the restack belongs to the stack tool. |
| error: the stack check could not run | a hint | The stack could not be verified either way. Run **Manual path** from its Stack guards; if those fail for the same reason, stop and report both failures. Never rebase an unverified branch. |
| error: a refusal naming commits | unpushed local commits, or origin commits the push would drop | Report the error text and stop. The tool is protecting those commits; the manual path would not. |
| any other error | the error text | Report it, then **Manual path**. |

| Thought | Reality |
|---|---|
| "The stack refusal came back, but I can see the MR targets the default branch, so I'll rebase by hand" | A stack refusal is the guard's verdict, not a hint. Only the stack-check-could-not-run error opens the manual path, and only through its own guards. |
| "`status: "synced"`, so now the push gate" | `branch_sync` already pushed; that is the fast path's contract. A push form for a push that happened is a false choice. Report it as pushed. |
| "The check could not run, so the safe move is to stop and ask" | The manual guards are the same check by other means. Run them; stop only when they fail too. |

## Manual path

For a `branch_sync` error saying the stack check could not run, or any
other error the table sends here: both guards, then the rebase, then the
gates below.

## Stack guards

Both checks run before any fetch or rebase; either one refusing ends the
run. A single-branch rebase is legal only when the branch is stack-free
in both directions. The GitLab tools take `repoName` = the worktree's
absolute path.

- **Child check:** look up the branch's open MR or PR (GitLab: the
  `mr_for_branch` tool with `branches` = the branch, then its
  `targetBranch`; GitHub: `gh pr view <branch>`). Targets anything other
  than the default branch: REFUSE, naming the target. A stacked branch
  rebases onto `origin/<target>` if it rebases at all; moving it onto the
  default branch destroys the stack.
- **Parent check:** list open MRs or PRs targeting this branch (GitLab:
  the `mr_list` tool, keeping the rows whose `targetBranch` is this
  branch; GitHub: `gh pr list --base <branch>`). Any hit: REFUSE, naming
  the dependents. Rewriting a parent's history strands every child on
  commits that no longer exist.

A GitLab tool error, or a result carrying `syncError`, means the guard
could not run: stop and report it, never read it as stack-free.

Either refusal is a restack signal: the chain moves together or not at
all. Say so and point at the stack tool (`gitq:sync` where available);
never improvise a multi-branch rebase here.

| Thought | Reality |
|---|---|
| "The pipeline needs the default branch's fix" | A stacked MR reaches the default branch through its stack root. Rebasing it there directly destroys the stack. |
| "Just this parent; the children catch up later" | The moment the parent rewrites, every child points at history that no longer exists. |
| "No open MR in either direction" | Then the branch is genuinely stack-free: proceed. |

## Rebase

Show what's about to replay, not just what replayed:

```
git -C <worktree> fetch origin
git -C <worktree> log --oneline origin/<default>..HEAD
```

Then call the `git_rebase` tool with `tree` = the worktree's absolute
path and `onto` = `origin/<default>`. A `status: "conflict"` result goes
to **On conflict**.

## On conflict: gate `conflict`

If the rebase reports a conflict (`status: "conflict"` from `branch_sync`
or `git_rebase`), stop immediately. One sentence listing the conflicted
files (the bundle's `unresolvedFiles`, the files `git_rebase` returned,
or the `UU` and similar rows of `git -C <worktree> status --porcelain`).
When a caller is composing this as a per-branch step, hand back to it
with that sentence; it owns the sweep's gates. Otherwise the gate:

- When this conversation holds a run's `runDb`: the `run_field_set` tool with that `runDb`, `key` `gate`, `value` `conflict:rebase-worktree:<attempt>`, `stage` `<run.current_stage>`.
- When this conversation holds a run's `runDb`, run gate-protocol's Runs
  integration with kind `conflict:rebase-worktree:<attempt>` and these
  questions, each its own question (never fold one list into another --
  a question over 4 options sends the whole gate to the wait queue):
  - `conflict`: **Leave the rebase in progress for me** (recommended) /
    **Abort the rebase** (the `git_rebase` tool with `abort: true`)
  - `next`: **Proceed** (recommended) / **Iterate here** / **Hold**

{{include:spawned-no-run-guard}}

- When this conversation holds a run's `runDb`: the `run_decision` tool with that `runDb`, `contract` `gate@1`, `scope` `conflict:rebase-worktree:<attempt>`, `selection` `{"next":"leave|abort|iterate|hold","note":"<their words or null>"}`, `decidedBy` `<the answer's by>`.

Never resolve the conflict yourself, `git add` the files, or run `git
rebase --continue` or `git rebase --skip`; abort only on that answer.

## After a clean rebase

Report the move as old head -> new head: note the branch's
`git -C <worktree> log -1 --oneline` before the fetch, then run the same
command again once the rebase finishes, and show both.

On the fast path the line ends with "pushed by branch_sync": the push is
done, and this section is finished. When a caller is composing this as a
per-branch step, hand that line back; it has nothing to gate for this
branch.

On the manual path pushing is a separate decision, gate `push`. When a
caller is composing this as a per-branch step, hand back the old head ->
new head line and let it gate the batch. Otherwise:

- When this conversation holds a run's `runDb`: the `run_field_set` tool with that `runDb`, `key` `gate`, `value` `push`, `stage` `<run.current_stage>`.
- The sentence is the old head -> new head line above; nothing else
  before the form.
- When this conversation holds a run's `runDb`, run gate-protocol's Runs
  integration with kind `push` and these questions, each its own question
  (never fold one list into another -- a question over 4 options sends
  the whole gate to the wait queue):
  - `push`: **Push with force-with-lease now** / **Leave it unpushed**
    (recommended when the branch has an open MR others may have pulled)
  - `next`: **Proceed** / **Iterate here** / **Hold**

{{include:spawned-no-run-guard}}

- When this conversation holds a run's `runDb`: the `run_decision` tool with that `runDb`, `contract` `gate@1`, `scope` `push`, `selection` `{"push":true|false,"next":"proceed|iterate|hold","note":"<their words or null>"}`, `decidedBy` `<the answer's by>`.

On **Push with force-with-lease now**, call the `git_push` tool with
`tree` = the worktree's absolute path and `forceWithLease: true`. Never
push unasked.

**These thoughts mean you are skipping the gate -- STOP:**

| Thought | Reality |
|---------|---------|
| "Push with force-with-lease now is the natural next action, so I'll mark it Recommended" | Only **Leave it unpushed** carries a recommended label, and only conditionally (an open MR others may have pulled). Render that qualifier attached to that option exactly; never move it to the push option. |
| "Restating the finding and explaining each option makes the ask clearer" | A gate's form is one sentence of context, then the bare option labels the gate text names, nothing more -- no restated heading, no per-option description, no conditional aside on when Hold applies. |

## Gate protocol

{{include:gate-protocol}}

## Wrap-up form contract

{{include:wrap-up-form}}
