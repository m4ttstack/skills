# Roadmap: install and upgrade friction

Deferred by Matt on 2026-07-27 until the current plan (parity, migration,
release readiness) is finished. Nothing here blocks that work.

## 1. Extension upgrades require a manual Chrome reload

Every runtime bump installs the extension to a NEW versioned directory, so
Chrome stays pointed at the previous path and never sees the new build. The
runtime half is already automatic; only Chrome needs a human.

Recommended fix: keep versioned directories as the verified store, but have
Chrome point permanently at one stable directory (for example
`~/.fast-browser/extension/current`) whose contents are swapped atomically
after the new content digest verifies, then have the extension service worker
call `chrome.runtime.reload()`. Load once, ever.

Design constraints already known:
- The content-manifest walker deliberately refuses symlinks, so `current`
  must be a real directory whose contents are replaced, not a symlink.
- Verify the new content BEFORE swapping and refuse to swap on failure. A
  self-reloading extension with no human in the loop must never be able to
  reload itself into a broken or unverified state.
- Chrome must be able to reload while a client is connected without
  stranding a session; check the reconnect path.

Later, if this ever ships beyond one machine: an unlisted Chrome Web Store
listing gives true auto-update with no path games (the manifest already pins
a key, so the extension id stays stable). A macOS enterprise policy
force-install is a heavier third option. Self-hosted `.crx` with `update_url`
is NOT viable: Chrome dropped off-store sideloading on macOS.

## 2. Old artifact directories accumulate forever

Nothing prunes `~/.fast-browser/runtime/*` or `extension/*`. Matt's machine
already carries runtime `0.1.0-alpha.1/5/6` and extension `0.2.1/2/3`. Beyond
disk waste, the leftovers were the precondition that made the upgrade-vs-
tamper misclassification reachable. Prune on successful upgrade, keeping at
most one previous version for rollback.

## 3. Failures are undiagnosable from the CLI

`setup`'s outer catch discards the underlying error entirely, so a real
failure surfaced only as "Setup failed; inspect the reported managed state
and retry." `uninstall` failed the same silent way. Diagnosing required
calling the library directly from Node. Redaction should not destroy
diagnosability: keep the fixed user-facing message, but preserve a cause
chain behind a flag or write it to a local log.

## 4. Setup mutates before it validates

Routing ownership is derived from `config.json`. With that file absent,
setup installed artifacts and only then failed, leaving a partial state.
Either reconstruct ownership from the managed files themselves, or fail
before mutating anything. This is the same shape as the original
2026-07-26 defect where routing was applied before config validation.

## 5. Smaller items

- `doctor` returns the same fixed message for "extension loaded from an
  unmanaged path" and "content drifted"; diagnosability could improve
  without echoing paths.
- `tests/integration/plugin-install.test.mjs` is genuinely flaky under
  concurrent test-file execution (reproduced on an unmodified baseline;
  passes in isolation and with `--test-concurrency=1`). Fix the isolation
  rather than living with it.
- The plugin's own version is still `0.1.0-alpha.1` while the runtime pin
  has moved to `0.1.0-alpha.6`. Deliberate (separate version axes), but
  decide the intended relationship before release.
