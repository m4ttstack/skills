# Fast Browser 0.1.0-alpha.4

Published to npm as `@mattstack/fast-browser@0.1.0-alpha.4` (dist-tag `latest`).

## Identity

| Field | Value |
| --- | --- |
| mattstack commit | `ad2cfe2` (on `main`) |
| Feature range | `6853a8f..eb60dcc`, 26 commits |
| Plugin version | 0.1.0-alpha.4 (was 0.1.0-alpha.3) |
| Runtime pin | unchanged, `runtime-lock.json` not touched by this release |
| Tarball | 77 files, 114.7 kB packed, 414.4 kB unpacked |
| Tarball shasum | `f0f2847b92feb19b5d4e6540c47744afa80562d1` |

Version bumped in all four declarations the release gates check: `package.json`,
`.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, and the repo-root
`.claude-plugin/marketplace.json`.

## What shipped

Screenshot annotation. An agent can annotate a browser screenshot with arrows,
highlights, labels and redactions whose coordinates are measured from the live
DOM rather than estimated from the image.

- `builtins/macros/capture-annotated.js` captures a PNG and measures named CSS
  selectors in a single page state. The screenshot-then-measure adjacency is the
  integrity guarantee; a selector matching zero or several elements is reported
  in `missed` and never resolved.
- `fast-browser annotate <config>` builds an SVG over the base PNG using eight
  primitives and pipes it to `rsvg-convert`. The SVG is never written to disk,
  because it embeds the unredacted screenshot as base64.
- `lib/annotate/palette.mjs` vendors Radix Colors scales; attribution is in
  `THIRD_PARTY_NOTICES.md`.
- `fast-browser configure --palette <name>` stores the choice.
- `fast-browser doctor` reports `annotate-renderer`, which never counts as
  install drift because annotation is optional.
- `skills/annotating-screenshots/` ships for both hosts.

Also fixed on the way, in `setup` and `configure`, and worth noting because they
are not annotation features:

- `configure` no longer resets session recording and retention on an unrelated
  change.
- `setup`'s reinstall branch no longer discards the annotation palette, no longer
  resets session recording and retention when the profile has not changed, and no
  longer drops the connection mode. The retention prune now reads the carried
  values rather than profile defaults, which would otherwise have deleted
  sessions a user widened their window to keep.

## Test results

| Suite | Result |
| --- | --- |
| unit + integration (`npm test`) | 510 pass, 0 fail |
| annotation e2e (`npm run test:annotate`) | 2 pass, 0 fail, real runtime and real `rsvg-convert` |
| release gates | included in `npm test`, all green |
| `npm pack --dry-run` | 77 files, no tests, sessions, macros, or local state |

The suite was run on the merged `main` before the version bump (510 pass) and
again after it (510 pass), so the gates that compare versions across the four
manifests ran against the bumped values.

## Verified live, not only in tests

- The `capture-annotated` macro was driven through the real
  `browser_run_code_unsafe` against a live page: correct `viewport.inner`
  `[900, 560]` and `client` `[885, 582]`, two selectors resolved, one reported
  `no-match`, one reported `ambiguous` with `count: 8`.
- The full pipeline (macro to config to CLI to raster) was exercised twice by
  independent verification runs producing correct annotated output.
- `rsvg-convert` 2.62.1.

## Known, recorded, not fixed

See `.local-dev/superpowers/2026-07-28-fast-browser-annotation-handoff.md` for
the two open decisions (built-in macro fixes cannot reach an existing install;
the tilde trap still latent for `page-recon`) and
`.superpowers/sdd/2026-07-28-fast-browser-annotation/deferred-findings.md` for
the 27 Minor findings the final review triaged as ship-as-is.

## Not done

`main` is **not pushed**. The npm package is public but the source commits are
local only, so `origin/main` is behind the published version. Push when ready.
No git tag was created; this repo has no tagging convention (zero tags).
