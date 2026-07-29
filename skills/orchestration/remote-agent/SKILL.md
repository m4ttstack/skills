---
name: mattstack:remote-agent
description: "Launch a Claude Code agent in a fresh herdr pane under a chosen cswap account and model, in a target repo, and enable /remote-control so it can be continued from your phone or claude.ai/code. Use when the user says 'remote-agent', 'launch a remote agent', 'spin up claude in <repo>', 'open a new pane and start claude', 'launch claude as <account>', 'remote-control a new session', 'beam a session to my phone', or asks to start a Claude Code session in another repo under a specific account/model."
---

# remote-agent

Spin up one Claude Code agent in a new herdr pane: pick the repo, the cswap
account, and the model, then hand it off to `/remote-control` so you can keep
driving it from your phone or the web. This is the single-shot cousin of
`mattstack:shepherdr` -- no worktrees, no job contracts, just "start a session
over there and let me continue it anywhere."

For herdr CLI mechanics, load the `herdr` skill.

## prerequisites

1. Confirm `HERDR_ENV=1`. If it is not set, stop -- this only works from inside
   a herdr-managed pane.
2. `cswap` must be on PATH if the user wants a specific account (it is at
   `~/.local/bin/cswap`). `cswap list` shows the managed accounts.

## the fast path

Run the bundled script -- it does every step below and prints a summary
(including the remote-control URL):

```bash
"$SKILL_DIR/scripts/remote-agent.sh" -r <repo-name|path> [-a <account>] [-m <model>]
```

`$SKILL_DIR` is this skill's directory (the folder containing this file).

Examples:

```bash
# repo-tools, as goodwin's account, on opus, remote-control on (all defaults but repo/account)
remote-agent.sh -r repo-tools -a goodwin.matthew.eric@gmail.com

# a repo by absolute path, sonnet, in a new TAB instead of a split pane
remote-agent.sh -r ~/Documents/GitHub/mr-board -a 2 -m sonnet -t

# current active account, default model, no remote-control
remote-agent.sh -r spritr -R
```

### arguments

| flag | meaning | default |
|------|---------|---------|
| `-r` | repo name (resolved under `~/Documents/GitHub`) or absolute path | **required** |
| `-a` | cswap account: email or list number | current active account (plain `claude`, no cswap) |
| `-m` | model alias for `claude --model` | `opus` (pass `-m ""` to inherit Claude's default) |
| `-t` | open a new herdr **tab** (labeled after the repo) | off -- splits a pane instead |
| `-d` | split direction (`right`/`down`/`left`/`up`) when not `-t` | `right` |
| `-R` | skip `/remote-control` | off -- remote-control is sent by default |

The script prints, on stdout:

```
pane: <pane-id>
repo: <resolved path>
account: <account or "current active">
model: <model>
remote_control: enabled|skipped
remote_url: https://claude.ai/code/session_...
```

Relay the `remote_url` to the user -- that link (and their phone) is the whole
point.

## mapping a request to flags

- "launch claude in **X** as **Y@** on **opus**" -> `-r X -a Y@ -m opus`
- no account named -> omit `-a` (uses the current active cswap account)
- "just start it, I'll drive it here" / "don't remote-control it" -> add `-R`
- "give it its own tab" -> add `-t`

If the user names a repo you can't resolve, run `ls ~/Documents/GitHub` and ask
which one; do not guess.

## what the script does (manual fallback)

If the script is unavailable, do this by hand:

1. Confirm `HERDR_ENV=1`; else stop.
2. Resolve the repo path (name -> `~/Documents/GitHub/<name>`, or use the path).
3. If an account was named, confirm it exists: `cswap list | grep -i <account>`.
4. Find your focused pane: `herdr pane list` -> the pane with `"focused": true`.
5. Split it (or open a tab):
   `herdr pane split <focused> --direction right --no-focus` and parse
   `result.pane.pane_id`.
6. Launch:
   `herdr pane run <pane> "cd <path> && cswap run '<account>' --share-history -- claude --model '<model>'"`
   (drop the `cswap run '<account>' --share-history --` part to use the current
   account). Keep `--share-history`: cswap re-syncs sharing on every launch, so
   omitting it unlinks that account's `projects/` and `history.jsonl` and the
   session's transcript lands in a profile-local dir that `claude --resume`
   elsewhere cannot see.
7. **Wait with `herdr wait agent-status <pane> --status idle --timeout 60000`.**
   Do NOT wait on banner text -- the wording varies and the match will time out
   (this was the original failure). Fall back to
   `herdr wait output <pane> --match "auto mode|❯" --regex`.
8. If remote-control is wanted:
   `herdr pane send-text <pane> "/remote-control"` then
   `herdr pane send-keys <pane> Enter`. **Watch the startup-greeting race:**
   some Claude configs auto-greet and "bake" for ~20s on launch, so the first
   `idle` fires *before* the greeting finishes and a command sent then is lost.
   If activation does not appear, re-wait `agent-status idle` and re-send the
   whole `/remote-control` text (not just an Enter nudge), up to a few times.
9. Grab the URL from `herdr pane read <pane> --source recent-unwrapped`, but
   **strip whitespace before matching** (`| tr -d '[:space:]'`): narrow panes
   wrap both the "is active" line and the URL across rows, so a plain grep
   misses them. Then match `https://claude.ai/code/session[_A-Za-z0-9-]+` and
   report it.

## notes

- Readiness detection (`agent-status idle`) is the load-bearing lesson: it is
  robust where banner-text matching is flaky (matching the launch banner text
  times out because the wording varies by version/model).
- The startup auto-greeting races the `/remote-control` send; re-wait idle and
  re-send the full text if activation is not confirmed.
- Panes wrap the URL and the "is active" line; whitespace-strip the snapshot
  (`tr -d '[:space:]'`) before matching either.
- `-a` accepts a number too (`cswap list` numbers accounts), handy when you
  don't want to type an email.
