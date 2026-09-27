# Work cutover: the digraph pipeline becomes work

Date: 2026-09-27. Ticket: RT-343 (parent RT-334, wave 6).

## Goal

One work pipeline. The digraph engines that shipped beside the prose ones
as `work-next` take the canonical names, the prose engines and every
`work-next` name retire, and runs record work type `work`. Team packs that
bind `work` and `stage-*` today compile unchanged apart from dropping their
`work-next` entries.

## Decisions

1. **Stage order is fixed in the graph** (settled at the design gate). The
   digraph `work` hard-codes the eight stages in its Stages table through
   `{{verb.path:stage-<stage>}}` and starts runs with
   `{{run-start.flags:work}}`, so runs record `--work-type work --pipeline
   work`. A pack's `pipelines` key survives only as the stage roster: it
   must list all eight `stage-*` engines. claimview already lists exactly
   the canonical eight in canonical order, so its `pipelines` block stays
   as it is. A pipeline naming a subset (rt's acme compile fixture: plan,
   implement, ship) fails compile loudly on the first `verb.path` whose
   stage is not rostered; that is an rt follow-up, not a runtime surprise.
   rt refuses a name that is both a roster verb and a pipeline stage, so a
   pack rosters the stages one way or the other; `pipelines` is the path
   of least change.
2. **Engines move in place of the prose ones.** Layout after the cutover:

   | Before (digraph) | After | Replaces (prose, deleted) |
   |---|---|---|
   | `attachments/work-next/work-next/` | `attachments/pipeline/work/` | `attachments/pipeline/work/` |
   | `attachments/work-next/work-next-<stage>/` | `attachments/pipeline/stage-<stage>/` | `attachments/pipeline/stage-<stage>/` |
   | `attachments/work-next-gate/` | `attachments/run-gate/` | nothing |

   `attachments/work-next/` disappears. Stage `<stage>` is each of
   provision, plan, gates, evidence, implement, self-review, ship,
   watch-ci; `stage-watch-ci` keeps its `scripts/` and `tests/`.
3. **The gate include is named `run-gate`.** Its body is already headed
   "Run gate" and its graph is `run_gate`; the name says what it is (the
   gate step under a run) without naming the retired pipeline.
4. **run-gate and gate-protocol stay separate in this job.** gate-protocol
   (444 lines) serves gated verbs with and without a run: forge verbs,
   review verbs, standalone ship and watch-ci, plus the off-script gate
   and wrap-up-form pairing. run-gate (139 lines) is the run-bracketed
   subset every pipeline stage needs. Merging would add about 300 lines to
   every stage verb or split gate-protocol's graph, and neither is
   trivial. They should converge later: gate-protocol's "under a run"
   branch should become an include of run-gate, so one graph owns the
   run-bracketed gate. Recorded as a follow-up.

## Engine edits (mechanical)

Inside the moved files, and nothing beyond this list:

- `name:` becomes the new directory name (`work`, `stage-<stage>`,
  `run-gate`).
- Descriptions: stages say "Reached only through the work orchestrator";
  `work` becomes a trigger-only description for running a unit of work
  end to end (no "beside work", no "digraph pipeline" framing);
  `run-gate` names pipeline stages and the work orchestrator.
- `{{verb.path:work-next-<stage>}}` becomes `{{verb.path:stage-<stage>}}`.
- `{{run-start.flags:work-next}}` becomes `{{run-start.flags:work}}`.
- `{{include:work-next-gate}}` becomes `{{include:run-gate}}`.
- The orchestrator heading becomes `# work -- the pipeline orchestrator`
  and its graph `digraph work`; run-gate's first line of prose says "the
  work pipeline".

Unchanged, by contract: every slot name and contract (`tiering`
model-tiering@1; `domain` with each stage's `*-domain@1`; `forge`
ci-forge@1), every `metadata.stage*` declaration, allowed-tools, and every
other `{{...}}` seam (`slot`, `stage.fields`, `stage.dir`, `include:
execution-strategy`, and the rest). A pack's fills bind the same slots
under the same engine names they bind today.

## Coupled fix: watch-ci scripts

The digraph `stage-watch-ci` carries a newer `ci-triage.sh` (a nonzero
failure count keeps a line even when it also reports passes) plus extra
test fixtures. `plugin/tests/test-resolve-args.sh` requires the standalone
`attachments/pipeline/watch-ci/scripts/` to be byte-identical to
`stage-watch-ci`'s for `ci-watch.sh`, `ci-triage.sh` and `ci-attendant.sh`.
The cutover copies the new `ci-triage.sh` into `watch-ci/scripts/` so the
identity holds and both verbs triage the same way.

## Docs and ledger

- `README.md` Pipeline section: work walks a fixed eight-stage graph; a
  pack rosters the stages (its `pipelines` array lists all eight); drop
  "the pipeline the compiler baked in from the consumer's manifest".
- `attachments/parameterized-skills/references/convention.md` "Pipeline
  resolution": the orchestrator's stage order is fixed; `pipelines` rosters
  stage engines for compile; `{{pipeline.stages}}` and `{{work-type}}`
  remain compiler placeholders with no mattstack engine using them.
- `plugin/schemas/skills-manifest.md` and the schema's `pipelines`
  description: the same roster meaning.
- `CERTIFICATION.md`: the 2026-09-26 work-next rows stay as history; new
  2026-09-27 rows for `work`, the eight `stage-*`, `run-gate` and
  `watch-ci` record the promotion. These rows and the history rows are
  the only intentional `work-next` mentions left.
- `.claude-plugin/plugin.json`: 0.25.2 to 0.26.0 in the cutover commit.

## Team pack changes (for the shepherd; no ticket ids)

claimview (`packs/claimview/`):

- `pack/stubs.jsonc`: delete the `work-next` verb and the eight
  `work-next-<stage>` verbs. Keep `work` (engine `work`).
- `pack/skills.jsonc`: drop `mattstack:work-next` from `skills.enabled`;
  drop the `mattstack:work-next` binding and the seven
  `mattstack:work-next-<stage>` bindings. Keep `pipelines.feature` and
  every `mattstack:stage-*` binding (their domains already match the
  work-next ones exactly).
- `pack/surface.jsonc`: drop `work-next` from `public`.
- Recompile; remove the stale compiled `skills/work-next/` and
  `attachments/work-next-*` dirs if the compile leaves them.

## Equivalence proof

No RED/GREEN rerun. Instead:

1. A scratch mattstack home whose `plugins/mattstack` points at this
   worktree, and a scratch copy of the claimview pack with the pack
   changes above applied. `rt skills compile --pack-dir <scratch pack>
   --mattstack-dir <scratch home>` compiles every verb with no errors and
   no `{{` left.
2. Baseline: the same compile against the base commit and the unchanged
   pack copy, plus the currently committed compiled `work-next` verbs.
3. A normalizing diff (rename map `work-next-<stage>` to `stage-<stage>`,
   `work-next-gate` to `run-gate`, `work-next` to `work`; compiled-version
   and pack-sha metadata; part-seam source paths and line ranges) shows the
   new `work` and `stage-*` equal the old `work-next` and `work-next-*`
   apart from names and the rewritten description lines.
4. acme: the rt fixture pack compiled against this worktree, once as-is
   (expected loud failure on the subset pipeline, captured for the rt
   follow-up) and once with its pipeline widened to the eight stages
   (compiles clean).

## rt follow-ups (read only here; report, do not change)

- acme compile fixture: its subset pipeline and fixture `work` engine
  model the retired prose shape; widen it to eight stages and a fixed
  order `work` when rt next touches the fixture.
- `rt skills init` seeds `pipelines.feature` with the eight stages
  (`lib/skills/init.ts`): still valid as the roster; its comments should
  say the order is fixed.
- `{{pipeline.stages}}` / `{{work-type}}`: no mattstack engine uses them
  now; the structural orchestrator check in `commands/skills.ts` (the
  unioned stage allowed-tools) no longer fires for work, which declares
  its own. Candidates for deprecation.
- Console wiring's `ORCHESTRATOR_VERB = 'work'` now points at the digraph
  orchestrator; no change needed. No rt code keys on `work-next`.
- Runs started before the cutover carry work type `work-next` or
  `feature`; nothing in rt filters on either.
- gate-protocol including run-gate for its run branch (decision 4).

## Verification

`sh tests/certify.sh` on every changed engine dir;
`bash plugin/skills/process-digraphs/test-check-dot.sh`; the strict pack
check as `.github/workflows/purity.yml` mcp-lint runs it;
`sh tests/repo-purity.sh`; `bash plugin/tests/test-resolve-args.sh`;
`git grep work-next` shows only the ledger and this job's dated docs; the
equivalence proof above.
