# shepherdr job brief template

Copy this template verbatim for every brief; fill the angle-bracket slots.
The question and report formats are embedded because workers never load
skills -- the brief is their only copy of the contract.

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

## Delegation
For searches, codebase exploration, and mechanical subtasks, dispatch
subagents on cheaper models instead of doing them in your own context.
Reserve your own turns for design decisions and the work itself.
