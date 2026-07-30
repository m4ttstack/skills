# Fast Browser 0.1.0-alpha.8 (plugin)

Published to npm as `@mattstack/fast-browser@0.1.0-alpha.8` (dist-tag
`latest`). Plugin-only release; the pinned runtime stays at the already
published `fast-browser-v0.1.0-alpha.8` fork release, unchanged.

## Identity

| Field | Value |
| --- | --- |
| Tarball | 84 files, shasum `8ab285571b666e96dda62fe77bbbfb570ba15797` |
| Feature range | `cbf31f5..` five commits plus the release chore |
| Runtime pin | unchanged, runtime 0.1.0-alpha.8 / extension 0.2.4 |

## What shipped

- MAT-89: the macro index and browser-macros skill stop documenting the
  bare/tilde `filename` call form the runtime refuses; both now demand the
  absolute written-out path and name the exact refusal, with tests pinning
  the invocation form against what the runtime accepts.
- MAT-90: setup's reinstall path states its config rewrite contract by
  construction (spread current, declare rewrites); a key-set test forces every
  future config field to be classified before the suite passes; a genuine
  profile change is announced in human output. The companion parse-args fix
  stops the CLI from turning an omitted `--profile` into `safe`, which had
  downgraded the same full-profile machine twice in one day, the second time
  after setup itself had learned to carry. Field-verified: a bare rerun keeps
  `full`.
- MAT-91: the browser-driver return contract makes delegated results carry
  their own evidence (selector or macro+key per claim, value verbatim, URL at
  read time, explicit miss list); routing guidance in both hosts names when
  not to delegate. Pinned by tests in both host variants.
- Launcher shim refuses a plugin root that cannot be quoted safely in
  /bin/sh (double quote, dollar, backslash, newline) instead of writing a
  shim that escapes its own quoting while doctor passes.

## Verified beyond the suite

- MAT-88 closed on live measurement against this exact stack: two delegated
  browser-driver sessions (HN multi-page, MDN nested-shadow-DOM compat
  table), 0 `browser_snapshot` calls in 21 browser tool invocations, ~1 KB
  distilled result per task in the parent context, both results honoring the
  MAT-91 contract.
- Suite at ship: 637 pass, 0 fail; publish gate (`macro-hashes --check`)
  passed before publish; alpha.8 recorded in the manifest after.

## Project state

Every fast browser ticket MAT-86 through MAT-113 is Done.
