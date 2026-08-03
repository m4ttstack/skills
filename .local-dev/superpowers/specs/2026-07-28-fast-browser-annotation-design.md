# Fast Browser screenshot annotation

Date: 2026-07-28
Status: revised after adversarial review; ready to plan

Revision note: the first draft split capture and measurement into two MCP calls
guarded by a viewport-width equality check. Review proved that guard does not
catch its own motivating failure (`innerWidth` is identical with and without a
scrollbar: 900/900, while `clientWidth` differs 885/900 and coordinates shift
15px). Capture and measurement are now a single atomic macro call, which
removes the failure class instead of checking for it.

## Problem

Fast Browser can capture screenshots but cannot mark them up. A raw capture
rarely makes its own point: the reader has to hunt for what changed, and there
is no way to hide PII in a shot that is otherwise worth sharing.

An existing internal screenshot-annotation skill already solves the *drawing*
half well. This design lifts that pipeline into Fast Browser essentially
unchanged and fixes the one part of it that does not survive being handed to
an agent.

## What is borrowed, and what changes

### Borrowed unchanged

`annotate.py`'s rendering pipeline: read the base PNG's dimensions from its
IHDR header, embed it as a base64 data URI inside an `<image>`, draw SVG
primitives over it, rasterise with `rsvg-convert` at 2x. Eight primitives:
`arrow` (quadratic bezier with a `bow` factor and a marker head), `chip`,
`highlight`, `box`, `ellipse`, `counter`, `blur`, `spotlight`. Same drop-shadow
filter, same marker definition, same JSON config shape.

This pipeline was evaluated against a Chrome-headless renderer on byte-identical
SVG input. Output was visually indistinguishable, but rsvg was ~7x faster
(0.43s vs 3.0s), Chrome did not exit on its own and had to be killed, and it
required a temp profile plus an HTML wrapper to suppress the default 8px body
margin. rsvg stays, as a hard dependency.

Three deliberate divergences from "unchanged", each argued in its own section
below: the SVG is piped to `rsvg-convert` rather than written to disk (it embeds
the unredacted screenshot); every config field is validated rather than trusted;
and byte-identical output is not a goal.

### Changed: coordinates are measured, not guessed

This is the change that motivates the feature, and the reason it is worth
building inside Fast Browser rather than shipping the Python script.

`annotate.py` takes raw pixel coordinates in base-image space. The calling
agent has to read the PNG, eyeball positions and estimate. The source skill
compensates with "keep highlight boxes generous so placement is forgiving" and
a mandatory re-read-and-verify step.

Measured during design: an agent generating coordinates that way, against a
900x560 screenshot of a typical card UI, placed four of eight primitives wrong.

| Target | Guessed | Real `boundingBox()` | Outcome |
|---|---|---|---|
| Name (PII, blur) | `[128,118,300,22]` | `[320,128,99,17]` | partial cover, **name still legible** |
| Estimate (highlight) | `[700,186,170,26]` | `[783,200,72,17]` | clipped the value |
| Phone (ellipse) | spans x 170-294 | starts x **307** | **zero overlap, complete miss** |
| Heading (counter) | y 120 | heading ends y 105 | sat below target |

The redaction failure is the important one: it leaves PII visible while looking
deliberate. Fast Browser is attached to a live DOM, so it can measure instead:
a selector either resolves to exact bounds or reports that it did not match.

### Explicitly not borrowed: the propose-then-confirm gate

Step A4 of the source skill requires the agent to propose annotations and wait
for confirmation before drawing. That gate exists because those screenshots
go into a merge request that a third-party reviewer reads, so the editorial
choice of what to point at needs a human.

Fast Browser annotates because the user asked for a screenshot and the user
receives the file. The feedback loop already exists and is cheaper than a
prompt. No confirmation gate.

The craft guidance from A4 *is* kept, as skill guidance rather than control
flow: which primitive suits which purpose; highlight boxes must fully enclose
the value; labels never sit on card content; never blur the value being proved.

## Architecture

Two independently testable halves that never touch each other's concerns:
**Playwright captures and measures together, Node draws.** Only a PNG path and
plain numbers cross the boundary.

```
1. browser_run_code_unsafe
     filename: capture-annotated.js  -> { png, viewport, resolved{}, missed[] }
       (one page state: page.screenshot() AND boundingBox() in the same call)
2. fast-browser annotate <config>    -> base-annotated.png
3. agent reads the PNG and reports
```

**Capture and measurement must happen in a single macro call.** They are not
two steps that happen to be adjacent. Splitting them across two MCP tool calls
puts an agent turn between them, during which a lazy image, a font swap, a
dismissed toast or a settling animation reflows the page. The boxes then
describe a layout the PNG does not show, and the result is a plausible-looking
artifact with a redaction in the wrong place. No equality check between the two
calls closes this: the first draft's viewport-width check was proven not to
catch even the simple scrollbar case it was written for.

`page.screenshot()` inside the macro captures at CSS pixels by default, so PNG
pixels equal `boundingBox()` units with no scaling.

### Components

| Path | Purpose |
|---|---|
| `lib/annotate/png.mjs` | IHDR dimension read; rejects non-PNG |
| `lib/annotate/palette.mjs` | Vendored Radix scales; name -> `{accent, soft, ink}` |
| `lib/annotate/svg.mjs` | The eight primitives; pure `(base, annotations, palette) -> string` |
| `lib/annotate/render.mjs` | `rsvg-convert` invocation via stdin, timeout, error mapping |
| `lib/commands/annotate.mjs` | CLI command; validation, containment, palette resolution |
| `builtins/macros/capture-annotated.js` | Atomic capture + selector measurement |
| `skills/annotating-screenshots/SKILL.md` | Workflow, vocabulary, composition rules |
| `skills/annotating-screenshots/agents/openai.yaml` | Codex-host skill artifact |

The `agents/openai.yaml` is not optional: this is a dual-host plugin and all
three existing skills ship one. Without it the workflow guidance is absent on
Codex.

### Changes to existing code

- `lib/macros/install.mjs` is hardcoded to a single builtin (`BUILTIN_NAME =
  'page-recon.js'`, `pageReconSection()`). Generalise to a list of builtins with
  a section extractor keyed by macro name. Its index-merge, no-overwrite,
  `O_NOFOLLOW` identity checks and containment behaviour are preserved exactly.
- `lib/core/paths.mjs` gains `screenshotsDir` (does not exist today).
- `lib/cli/parse-args.mjs` gains the `annotate` command, `--palette`, and
  **positional-argument support** -- the parser currently throws `UsageError` on
  any non-flag token, so `annotate <config>` needs new machinery.
- `lib/cli/main.mjs` gains `annotate` in its `commands` registry and a
  `humanReport` branch.
- `lib/doctor/checks.mjs` gains an `annotate-renderer` check, added to
  `DOCTOR_CHECK_IDS`.
- `lib/core/config.mjs` gains `annotation.palette`.
- `lib/commands/configure.mjs` accepts `--palette` (see the constraint below).

### `configure --palette` must not have side effects

`configure` recomputes session settings from **profile defaults**, not from the
current config:

```js
const days = retentionDays(request.retentionDays ?? defaults.retentionDays);
const enabled = request.recordSessions ?? defaults.enabled;
```

`profileDefaults('full')` is `{ enabled: true, retentionDays: 30 }`. So a
full-profile user who ran `--no-record-sessions` and later sets a palette would
have **session recording silently switched back on** by choosing a colour. It
also hard-requires Codex CLI version detection when the codex host is
configured, so `--palette` would fail outright on a machine where Codex was set
up and later removed.

The palette setter must preserve current values. The codebase already has the
pattern in `selectedProfile()` (keyed off `request.explicitOptions`); apply the
same to sessions, and skip the routing transition entirely when only
`--palette` was passed.

## The capture-and-measure step

`capture-annotated.js` follows the existing macro contract
(`async (page, args) => result`, failures as `{ failedStep, error, url }`).

```js
args: { targets: { name: '#nm', estimate: '#est', cta: 'role=button[name="Submit"]' },
        out: 'claim-detail' }

returns: {
  schemaVersion: 1,
  png: '/Users/…/.fast-browser/screenshots/claim-detail.png',
  viewport: { inner: [900, 560], client: [885, 560] },
  resolved: { name: [320,128,99,17], estimate: [783,200,72,17] },
  missed:   [{ key: 'cta', reason: 'no-match' }]
}
```

Rules:

- **Screenshot first, measure second, same call, no `await` on anything that
  could reflow between them.** This is the whole integrity guarantee.
- **A selector matching more than one element is an error, not a first-hit.**
  Silently taking element 1 of 4 is how a redaction lands on the wrong row.
  Returns `{ key, reason: 'ambiguous', count }`.
- An element that is not visible, or has a zero-area box, is `missed`, not a
  zero box.
- **A box not fully inside `[0, 0, W, H]` is `missed`, reason `out-of-view`.**
  `boundingBox()` happily returns `y: 1200` for an element scrolled below the
  fold. SVG outside the viewBox rasterises to nothing, so without this rule the
  command succeeds, the blur covers nothing, and the agent reports a redaction
  that does not exist.
- `missed` entries never produce annotations. The agent is told, and reports it.
- Both `inner` and `client` viewport widths are reported. `innerWidth` alone
  cannot detect a classic scrollbar (it counts the scrollbar's pixels);
  `clientWidth` is what changes. The annotator uses them only as a corroborating
  sanity check against the PNG -- atomicity, not the check, is what makes the
  coordinates trustworthy.

### Macro payload versioning

`installBuiltinMacros` uses `copyWithoutOverwrite`, so once installed the macro
is user-owned and never updated -- deliberate, and correct for `page-recon`.
But unlike `page-recon`, this macro's output is consumed by another component as
ground truth for redaction placement, and a future release cannot ship a
contract change to it.

So the payload carries `schemaVersion`, and `annotate` rejects an unknown or
missing version with a message telling the user to remove the macro and rerun
setup. A stale or hand-edited macro must fail loudly rather than yield plausible
wrong boxes. `annotate` also needs a distinct error for "measure macro not
installed", since existing installs only receive it on the next `setup`.

## `fullPage` is out of scope for v1

`boundingBox()` is viewport-relative. Translating boxes into full-page space by
adding scroll offsets misplaces every `position: fixed` or `sticky` element: a
header measured at `y: 0` while scrolled 500px down becomes `y: 500`, while
Chromium's full-page capture renders it once near the top. Lazy and
`content-visibility: auto` content can also render during a full-page capture in
ways the measurement never saw.

Viewport-only is the honest scope. If full-page annotation is wanted later it
needs its own design, not a scroll-offset addition.

## Palettes

Built from Radix Colors, using its scale semantics directly:

| Role | Radix step | Used for |
|---|---|---|
| `accent` | 9 (solid) | arrow strokes, box/ellipse borders, counter fill, **highlight fill at 14% opacity** |
| `soft` | 3 (subtle component bg) | chip fill only |
| `ink` | 11 (accessible text) | chip label text |

Highlight fill is `accent` at 14%, matching `annotate.py` line 85. It is **not**
`soft`: Radix step 3 is near-white (`#f4f0fe`), and at 14% opacity over a light
UI it would be invisible.

This is the same trio `annotate.py` hardcoded (`#7C4DFF` / `#EDE7FF` /
`#4527A0`), except Radix guarantees step 11 on step 3 meets contrast rather
than relying on a hand-picked pairing.

**Default: `violet`** (`#6e56cf` / `#f4f0fe` / `#6550b9`) -- the closest of all
31 Radix scales to the existing `#7C4DFF`, by weighted-RGB distance.

First-use picker offers ten:

- purples: `violet`, `iris`, `indigo`
- high-contrast: `crimson`, `red`, `orange`
- cool: `teal`, `cyan`, `grass`
- neutral: `slate`

`config.json` accepts **any** of the 31 Radix scale names, not just the ten.

Radix Colors is MIT. The needed subset (10 scales x 3 steps) is vendored as
data in `lib/annotate/palette.mjs` rather than added as a dependency -- the
plugin currently has zero runtime dependencies and that is worth preserving.
Attribution is added to `THIRD_PARTY_NOTICES.md`.

### First-use choice

`config.annotation.palette` is absent by default, and the first annotation must
choose one. **The agent asks, not the CLI.**

This is forced by how the command is actually invoked. `confirmTty` returns
`false` whenever stdin is not a TTY, and an agent spawning `fast-browser
annotate` is never a TTY -- so a prompt inside the CLI would silently never
fire. Putting the question in the CLI would mean it is only ever asked of
humans running the command by hand, which is the rarer case.

So:

- **CLI**: with no palette stored, `annotate` exits with a `UsageError` naming
  the ten options and the command to set one. It does not guess a default and
  does not draw. Idempotent and identical in TTY and non-TTY.
- **Skill**: instructs the agent that on the first annotation it presents the
  ten palettes to the user, then runs `fast-browser configure --palette <name>`
  once. Every later annotation is silent.
- `fast-browser configure --palette <name>` changes it at any time.

`violet` is the *recommended* default the skill puts first, not a silent
fallback -- the point of the setting is that the user picked it.

Absent-means-unset needs no `schemaVersion` bump: `parseConfig` builds its
result from known keys, so existing v1 configs load unchanged.

## rsvg-convert as a hard dependency

- `doctor` gets an `annotate-renderer` check: present -> `pass` with version;
  absent -> `fail`, remediation `brew install librsvg`.
- `annotate` fails with the same message rather than producing a broken file.
- Not required by `setup`. Annotation is optional; a user who never annotates
  should not be forced to install it.

## Error handling

| Condition | Behaviour |
|---|---|
| `rsvg-convert` missing | fail with `brew install librsvg` |
| base is not a PNG | fail on the IHDR check |
| no palette configured | `UsageError` listing the ten and the configure command |
| measure macro not installed | fail, pointing at `fast-browser setup` |
| unknown/missing payload `schemaVersion` | fail; do not draw from an unversioned payload |
| PNG width matches neither `inner` nor `client` width | **refuse to draw**, report all three |
| selector no match | reported in `missed`, no annotation drawn |
| selector ambiguous | error with match count |
| box not fully inside the PNG | reported in `missed` as `out-of-view` |
| `out` == `base` | refuse; the original is always preserved |
| output outside `screenshotsDir` | refuse via `assertConfinedPath` |
| rsvg non-zero / timeout | fail, remove any partial output |

**Output is confined to `~/.fast-browser/screenshots/`.** The first draft said
both "an absolute `out` path honoured" and "refuse via `assertConfinedPath`",
which cannot both be true: `assertConfinedPath` structurally requires the root
to be a descendant of `dataDir`. Containment wins; `out` is a name, not a path.
Note that `uninstall --purge-data` therefore destroys annotated output, which
the skill should say plainly.

Errors follow the existing `LifecycleError` / `UsageError` shape so `--json`
reporting stays uniform.

### No intermediate SVG on disk

`annotate.py` writes the generated SVG beside its output and deletes it only on
success. That SVG embeds the **full, unredacted** screenshot as base64. For a
feature whose job includes redaction, a crash between write and rasterise leaves
the un-redacted image on disk, and a pre-existing `<out>.svg` gets clobbered.

`rsvg-convert` reads from stdin, so the port pipes the SVG in and never
materialises it. This is a deliberate divergence from "borrowed unchanged", and
the reason is worth keeping in the code comment.

### Input validation, not ported trust

`annotate.py` interpolates `counter.n` into markup unescaped and assumes every
field is well-typed. The Node port validates each annotation's type, numeric
range and string content before building markup. Borrowing the pipeline does not
mean borrowing its trust in its own config file.

## Profile interaction

`SAFE_POLICY` in `lib/hosts/routing.mjs` sets `browser_run_code_unsafe` to
`approval_mode = "prompt"`, and **safe is the default profile**. So on a default
install the capture-and-measure step raises an approval prompt every time. That
is correct posture, not a bug, but it materially shapes the feature's feel for
the majority configuration and must be stated in the skill so the agent expects
it rather than treating the prompt as a failure.

## Testing

**Fidelity is verified by rendered pixels, not by byte-identical SVG.** The
first draft claimed a byte-identical golden against `annotate.py` would prove
fidelity unchanged. That is false, and measured:

| Divergence | Python | Node | Reaches |
|---|---|---|---|
| float repr of integral values | `Q 150.0` | `Q 150` | every arrow (control points are always floats) |
| `.0f` vs `toFixed(0)` at `.5` | `2.5 -> 2` | `2.5 -> 3` | chip w/h/rx, counter r |
| entity choice | `&#x27;` `&quot;` | `&#39;`, quotes often unescaped | any chip text with quotes |
| `len()` vs `.length` | code points | UTF-16 units | chip default width for astral text |
| blur/spotlight filter ids | one shared counter | diverges if per-type | configs interleaving both |

Byte-equality is therefore reachable only by deliberately emulating Python float
repr, banker's rounding, `html.escape` entity choices and code-point lengths.
That is not worth doing: the deliverable is a correct artifact, not
bit-compatibility with a script that is not being shipped. A single golden would
also fail to exercise any of these.

So:
- **Rendered comparison** (the fidelity guarantee): rasterise a fixture config
  and compare against a stored golden PNG within a tight pixel tolerance.
- **Structural comparison**: parse both SVGs and compare element/attribute
  semantics with numeric tolerance, not string equality.
- **Adversarial fixtures** covering each row above: integral arrow midpoint,
  values landing on `.5`, chip text containing `'`/`"`/`&`, astral-plane chip
  text, and a config interleaving `blur` and `spotlight`.

Unit:
- `png.mjs` against valid, truncated, and non-PNG inputs.
- `palette.mjs`: known names resolve; unknown names error; all 31 scales
  resolve, not just the ten offered.
- `annotate` with no configured palette exits `UsageError` and draws nothing,
  in both TTY and non-TTY.
- A box extending past the PNG bounds is refused, not silently clipped.
- An unversioned or unknown-version measure payload is refused.
- `render.mjs` errors when `rsvg-convert` is absent (injected PATH), and writes
  no `.svg` anywhere on the failure path.
- Generalised macro installer: two builtins, index merge, idempotent reinstall,
  no overwrite of a user-edited macro, `O_NOFOLLOW` identity checks intact.
- `configure --palette` alone preserves `sessions.enabled`,
  `sessions.retentionDays` and `profile`, and does not require Codex detection.

Integration:
- End-to-end `annotate` on a fixture PNG produces a valid PNG at `base*scale`.
- Doctor reports `annotate-renderer` in both states.
- `release-gates`: the new builtin macro, the skill, and its `agents/openai.yaml`
  are packed; the vendored palette carries its MIT notice.

## Non-goals

- Before/after pairing, MR upload, evidence-directory conventions. Those are
  that other skill's workflow, not a generic annotation feature.
- Annotating PNGs that Fast Browser did not capture. Without a live DOM there
  are no measured coordinates, which is the whole point.
- New primitives. The eight are proven; `crop` is listed in the source skill's
  vocabulary but is not implemented in `annotate.py`, and stays unimplemented
  here so the documented set matches the real set.
- Live-page overlay drawing. Rejected: it mutates the user's real page, can
  trip an app's `MutationObserver`, and leaves graphics behind if it crashes.
- `fullPage` captures. See the section above -- scroll-offset translation
  misplaces fixed and sticky elements, and needs its own design.
- Byte-identical parity with `annotate.py`. Explicitly abandoned; see Testing.

## Follow-ups (out of scope, filed separately)

- **Session retention bug.** `runtimeArgs` passes `--output-dir=${paths.dataDir}`
  so the runtime writes `session-*` into `~/.fast-browser/`, but `pruneSessions`
  only scans `dataDir/sessions` and `dataDir/archive`. Live sessions are never
  pruned (40 present on the dev machine). Unrelated to annotation, but
  `~/.fast-browser/screenshots/` should be added to retention when it is fixed.
