# Baseline: creating a pack without the skill

Run 2026-09-24 in a clean-room guest (Tart clone of the release golden) with the merged rt on `main`, the mattstack plugin at `pack-authoring`, superpowers installed, a team zone `scratch` with no pack, and the test repo cloned at `~/repos/api`. The agent had no `creating-a-pack` skill. Prompt, verbatim:

```
We want the mattstack work pipeline on this repo. Set it up so /<team>:work runs. Our team is called scratch.
```

## What the agent did (34 seconds, seven tool calls)

1. Loaded `mattstack:editing-skills` as its guide (the publish skill, not a creation guide).
2. `ls ~/.mattstack/teams/; rt --help; rt skills --help`, then: "`rt skills init` looks like exactly this. Let me check its help and the scratch team state."
3. `rt skills init --help`, listed the zone, `rt skills packs`, `rt repos --help`. "The scratch zone exists with no pack yet, that's what `rt skills init` scaffolds. Running it for this repo."
4. `rt skills init --repo ~/repos/api --zone scratch` (human output, no `--json`).
5. Verified: `git remote -v`, the pack tree, `plugin.json`, `rt skills check --pack scratch`, the installed cache dir, the materialized manifest, the zone's git status.
6. "As the skill's final validation step requires, I'll read the compiled `work` verb in full from the installed cache." Read the compiled `work` skill and grepped for `{{`.
7. Stopped with a summary (quoted below) and a question.

Final message, verbatim:

> I set up the scratch team pack and installed it as `scratch@scratch` 0.1.0. `/scratch:work` will be available after you restart Claude Code, because the running session still uses the old plugin cache.
>
> **What `rt skills init` did:**
> - **Created the pack** at `~/.mattstack/teams/scratch/mattstack/packs/scratch`. It has the `work` command plus the default feature pipeline: provision, plan, gates, evidence, implement, self-review, ship, then watch-ci.
> - **Registered this repo** (`gitlab.com/acme/glance-test-repo`) with the feature pipeline, the default model-tiering setting and GitLab CI watching.
> - **Built and installed it:** `rt skills check --pack scratch` reports all 9 skills as current. I read the whole built `work` skill in the install folder and all the placeholders are filled in.
>
> **Not done yet:** the new pack files are only on this machine. In the team repo, the pack and `team.jsonc` are untracked and `marketplace.json` is modified, so teammates can't install it. I didn't commit or push, because pushing the team repo publishes the pack to everyone on the team. Do you want me to commit and push it?
>
> After restarting, run it from this repo with `/scratch:work <ticket>`.

## What it got right

The verb is discoverable from `rt skills --help`, and the agent ran it correctly, verified with `check`, read the compiled verb, and knew a restart was needed. No hand-rolled directories, no copied pack, no repo-local manifest.

## Where it stopped short

- No prerequisite check before running: daemon up, mattstack and superpowers installed, `claude` on PATH. It happened to be fine here.
- Ran init without `--json`, so a refusal would have been prose to parse rather than a code to branch on.
- Never proved the pipeline: no restart, no `/scratch:work` run, no report of the generic fallbacks the first run takes.
- Never asked the team whether they have rules to bind now (the one question the pack exists to ask), and never pointed at `extending-a-pack` for later.
- Ended on "do you want me to commit and push?" instead of the publish path (`mattstack:editing-skills`: commit, push, update, restart), leaving the pack local.
- Reached for `editing-skills` as the guide for creation; it is the guide for publishing.

## Classification

Not a discipline failure and not a wrong-shape failure: the agent complied and the artifact was right. It omitted required elements from a flow it otherwise performed. Per writing-skills "Match the Form to the Failure", the skill is a recipe that states the flow's parts in order (prerequisites, init with `--json` and its envelope, restart and prove, offer the first rules once, publish), each a required step, with the envelope's exact fields so the agent branches on codes rather than prose.
