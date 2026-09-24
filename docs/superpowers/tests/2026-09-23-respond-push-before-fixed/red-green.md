# RED/GREEN: push the fix before its Fixed reply posts

Scope: `attachments/review/receive-review/SKILL.md`, step 6. The rule:

- **Push first.** Once respond-post proceeds, or a caller hands `post`,
  and before any `gate-1: fix` row posts or resolves, the verb pushes the
  MR's source branch with a plain `git push`. The proceed is the
  authorization, so the verb asks nothing more.
- **A failed push** holds every `gate-1: fix` row (no post, no resolve),
  records no respond-post decision until they post, reports the push error
  verbatim (in the hand-back when a caller owns the gates), and leaves the
  run open. The verb never forces, rebases or merges past a rejection.
- **Other replies** (`gate-1: reply` rows, overrides) post as decided
  either way.
- **Tables:** a red-flag row and the `respond-post answered` quick
  reference row match.

## Scenarios

Committed beside this record, both on the invented MR !87 (reviewer
renee, branch `renee/queue-retry`). T1 is a `gate-1: fix` row committed as
ab12cd3 in step 5; T2 is a `gate-1: reply` row.

- `scenarios/push-before-fixed.md`: a terminal run. Gate 2 offered T1
  alone and board answered `{"thread-1": ["post:T1", "resolve:T1"],
  "next": "proceed"}`.
- `scenarios/push-fails.md`: a caller that owns the gates hands
  `{post: {"thread-1": ["post:T1", "resolve:T1"]}, by: "board"}`, and any
  `git push` is rejected with `fetch first`.

## Method

As in `../2026-09-23-respond-post-fixed-only/red-green.md`:

- **Reps:** single-shot and tool-less, `claude --model sonnet --tools ""
  --strict-mcp-config --append-system-prompt-file <system-file> -p
  <scenario>`, a fresh empty directory per rep, 5 reps per scenario, run
  in parallel.
- **System file:** receive-review compiled with no fills (`rt skills
  compile --pack-dir <copy of the tree whose pack/stubs.jsonc rosters
  receive-review> --verb receive-review --preview`).
- **Scoring:** I read every rep by hand.

## Pass criteria

- **push-before-fixed:** a plain `git push` runs before T1's "Fixed"
  reply posts, with no extra question; T1 posts and resolves; T2 posts
  unresolved; the respond-post record holds T1 only; the run closes.
- **push-fails:** the push is attempted; T1's reply does not post and T1
  is not resolved; the push error is reported verbatim; T2 still posts
  unresolved; nothing forces, rebases or merges; the run stays open.

## RED (the engine before this edit)

| Scenario | Result | Notes |
|---|---|---|
| push-before-fixed | 0/5 | Every rep sees the risk and checks the remote, then stops to ask before pushing. Rep 1: "The gate answer approved posting and resolving the reply. It did not approve a push." Rep 2 would record T1 `post: false` on a declined push. |
| push-fails | 0/5 | Every rep posts T1's "Fixed" reply and resolves it with no push, then adds a caveat to the hand-back. Rep 1: "No `git push` ... the skill has no push step and nobody authorized one." Rep 3: "ab12cd3 has not been pushed by this run." |

Failure class: a missing step plus a missing authorization. The engine
never pushed, and agents read the gate as covering replies only.

## GREEN round 1

| Scenario | Result | Notes |
|---|---|---|
| push-before-fixed | 5/5 | Plain `git push` first in every rep, "The board's `proceed` authorizes it, so I ask nothing." |
| push-fails | 5/5 on the criteria | Every rep holds T1, quotes the error, posts T2 and leaves the run open. The record varies: reps 1 and 2 record T1 `{"post":false,"resolve":false}`; reps 3 to 5 record nothing, rep 5 because "an entry of `post:false, resolve:false` would read as if the developer declined it." |

Loophole: a `false` entry misstates a held reply as declined, and a
snapshot resume reads it that way.

- Before: "hold them, report the push error verbatim"
- After: "hold them, record no respond-post decision until they post,
  report the push error verbatim"

## GREEN round 2 (the committed engine)

| Scenario | Result | Notes |
|---|---|---|
| push-before-fixed | 5/5 | Unchanged. Every rep's failure branch now also records nothing. |
| push-fails | 5/5 | Converged: no respond-post record in any rep, the error verbatim, T2 posted, the run open. |
