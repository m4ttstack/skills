# Baseline: extending a pack without the skill

Run 2026-09-24 in the same clean-room guest as the creating-a-pack baseline, with the `scratch` pack present and published (zero fills), the merged rt on `main`, mattstack at `pack-authoring` (0.19.4, which had no `extending-a-pack` yet). Prompt, verbatim:

```
Our pipeline shipped an MR without running `bun run lint`. Make the pipeline always run lint before it opens an MR on this repo.
```

## What the agent did (two minutes, 29 tool calls)

1. Looked in the repo first: `.mattstack/skills.jsonc` (absent), `package.json`, `.gitlab-ci.yml`, then the installed pack's `pack/skills.jsonc` and the manifest schema doc.
2. Loaded `mattstack:editing-skills` as its guide.
3. Read the compiled `attachments/stage-ship/SKILL.md` and `stage-self-review/SKILL.md` in the pack ("I'm tracking down where the scratch pack's `work` pipeline checks things before `stage-ship` opens the MR, so I can add `bun run lint` there"), then the engine's `stage-ship` source in the plugin cache and its `{{slot:domain}}` marker, the parameterized-skills convention, and the stale `templates/domain-pack/README.md`.
4. "The `ship` stage has an optional `domain` slot that's currently empty. I'm adding a scratch-pack fill there that runs `bun run lint` before the push."
5. Wrote `attachments/ship-lint/SKILL.md` with `disable-model-invocation: true` and `metadata.provides: "ship-domain@1"`, but a description that describes the fill's job ("Ship-stage fill: run the repo's lint script and require it to pass ... Reached only through a slot binding; not for direct invocation") rather than the contract's trigger form.
6. `rt skills bind stage-ship domain scratch:ship-lint --pack scratch` (a dry run first, then live), diffed the compiled `work` skill and `pack/skills.jsonc`, confirmed the per-repo manifest and the fragment carried the binding.
7. Ran `bun install` and `bun run lint` in the test repo as a "trial lint run" (which created a stray `bun.lock` it then deleted).
8. Bumped the pack to 0.1.1, committed to the zone, pushed, tried `rt skills sync` (refused: no mattstack marketplace registered in that guest), then `claude plugin update scratch@scratch`.

Final message, verbatim (opening):

> From now on, the `work` pipeline runs `bun run lint` before it pushes a branch or opens an MR. If lint fails, the ship stage stops and nothing is pushed. It takes effect after you **restart Claude Code**, because the running session still has the old version loaded. I haven't run a full pipeline end to end, so the next real run is the first live test.

## What it got right

The right place (a fill on the ship stage's `domain` slot, not the compiled stage, not the engine, not the repo), the contract in the frontmatter, `rt skills bind`, the fragment check, a version bump, a commit and push, a plugin update, and a clear restart note.

## Where it went wrong or stopped short

- **No baseline, no proof.** It never ran the stage without the rule to see the miss, and said so itself: "I haven't run a full pipeline end to end, so the next real run is the first live test." `superpowers:writing-skills` was never loaded. The trial it did run (`bun run lint` in the repo) tests the repo's lint, not the pipeline's behavior.
- **No certification.** `tests/certify.sh <fill dir> --domain` never ran.
- **Description in the wrong form.** The fill's description explains what the fill does; the convention is the trigger-only "Use when mattstack:<engine> resolves its <slot> slot here ..." form, which certify checks.
- **Fill body restates the engine.** Steps 3 and 4 spell out the push and MR flow the stage already owns; the rule is the lint gate and its failure action.
- **Side effect in the author's repo.** `bun install` ran in the checkout to try the lint script.
- **Read the retired template** (`templates/domain-pack/README.md`) as reference, which Task 12 removes.

## Classification

Mixed, as the plan predicted. The shape was right (fill, bind, publish), so the recipe stays short and points at `slots.md`. The misses are discipline: skipping the RED pass and certify because the mechanics were already in hand, and restating the engine in the fill. Those get a required sub-skill line, a required certify step, and a short red-flags list rather than a prohibition-first skill.
