# Fast Browser 0.1.0-alpha.6

Published to npm as `@mattstack/fast-browser@0.1.0-alpha.6` (dist-tag `latest`).

## Identity

| Field | Value |
| --- | --- |
| mattstack commit | `8f44920` (on `main`) |
| Feature range | `b47fdaf..8f44920`, 6 commits |
| Plugin version | 0.1.0-alpha.6 (was 0.1.0-alpha.5) |
| Runtime pin | unchanged, `runtime-lock.json` not touched by this release |
| Tarball | 79 files, 130.9 kB packed, 461.2 kB unpacked |
| Tarball shasum | `d311f42956c582e01728a14ae051e2ec1a40b77f` |

Version bumped in all four declarations the release gates check: `package.json`,
`.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, and the repo-root
`.claude-plugin/marketplace.json`.

## What shipped

The three follow-ups filed against 0.1.0-alpha.5: MAT-97, MAT-98, MAT-99. One
user-visible change, the rest test and release machinery.

- The setup note about preserved built-in macros no longer calls them edits.
  Preserving proves only that the installed bytes match no published version,
  and an install made from a working tree between releases holds exactly such
  bytes with nobody having touched them. The note now states the evidence and
  names the remedy (MAT-99).
- `scripts/generate-macro-hashes.mjs --check` runs from `prepublishOnly`, and a
  release gate asserts that wiring so it cannot quietly become nothing again.
  Its failure message separates a hash the tarballs hold and the file does not,
  which strands installs, from a hash the file holds and the tarballs do not,
  which is an unverifiable claim (MAT-98).
- A new offline release gate holds the hash manifest history-wide. Plain
  append-only is the wrong rule here, because the generator rebuilds from
  published tarballs plus the working tree and a hash recorded for an unreleased
  working-tree state legitimately disappears when that state is superseded
  before it ships. The gate recomputes each revision's own bytes to exempt
  exactly that case (MAT-98).
- `tests/e2e/affordances.test.mjs` runs `page-affordances.js` through the real
  runtime against a new fixture page. Its load-bearing assertion is that every
  selector the macro emits resolves, in Playwright, to exactly one element
  (MAT-97).

Also fixed on the way, and worth noting because it was blocking every e2e suite
rather than only the new one:

- The default local-runtime release directory was a fixed run of `..` segments
  written from a worktree two levels deeper than a plain checkout, so any e2e
  run from the repository itself failed on ENOENT before the first browser call.
  It is now found by walking up from the plugin root.

## Test results

| Suite | Result |
| --- | --- |
| unit + integration (`npm test`) | 568 pass, 0 fail |
| affordances e2e (`npm run test:affordances`) | 5 pass, 0 fail, real runtime |
| annotation e2e (`npm run test:annotate`) | 2 pass, 0 fail, real runtime and real `rsvg-convert` |
| release gates | included in `npm test`, all green |
| publish gate (`--check`) | passed before publish |

The suite was run on the merged `main` before the version bump and again after
it, so the gates that compare versions across the four manifests ran against the
bumped values.

## Verified by mutation, not only by passing

Both new gates were shown to fail on the defect they exist for, then restored.

- Dropping the hidden-subtree check from `contentName` in `page-affordances.js`
  makes `role=button[name="Cancel"]` resolve to zero elements, and the selector
  assertion fails. This is the macro-computes-accessible-names divergence the
  ticket asked to pin.
- Deleting a published hash from the manifest, on a temporary commit whose
  working-tree bytes differed from it, fails the append-only gate with a message
  naming the offending revision.

One incidental finding from a second mutation: making `roleOf` claim `textbox`
for a password input did NOT break the selector assertion, because Playwright
does resolve `role=textbox[name="..."]` against a password input. The macro is
stricter than Playwright there rather than wrong, which is the safe direction
and is what its comment already claims.

## Known, unchanged

`tests/integration/plugin-install.test.mjs` still fails intermittently under
subprocess load (once in three full-suite runs here, clean on rerun and clean
when run alone). Nothing in this release touches its path.

## Not done

No git tag was created; this repo has no tagging convention (zero tags).
