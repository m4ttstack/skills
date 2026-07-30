# Fast Browser 0.1.0-alpha.7 (plugin) + runtime 0.1.0-alpha.8

Two coordinated releases: the runtime gained video recording, the plugin
gained everything from MAT-110 through MAT-113.

## Identity

| Field | Value |
| --- | --- |
| Plugin | `@mattstack/fast-browser@0.1.0-alpha.7`, npm dist-tag `latest` |
| Plugin tarball | 84 files, 147.7 kB packed, shasum `76f83d25cdaac6292d0a3996a500a4735e9dd9b3` |
| mattstack commit | `cbf31f5` on `main`, pushed |
| Runtime | `fast-browser-v0.1.0-alpha.8` GitHub release on `m4ttheweric/playwright`, 3 assets |
| Runtime source | fork commit `5763ccf8` on `fast-browser-runtime`, pushed |
| Runtime tarball sha256 | `709c6cab...f4ac2`, verified by downloading the published asset |
| Extension | 0.2.4, byte-identical to alpha.7 (`764beb8d...`) |

## What shipped (plugin, since alpha.6)

- MAT-110: setup installs a managed launcher shim at `~/.local/bin/fast-browser`
  on every outcome; doctor `launcher` check detects missing/foreign/stale;
  uninstall removes it marker-gated only when no hosts remain.
- MAT-111: `annotate` import mode for PNGs from outside the capture flow;
  dimensions from the PNG replace the measured check; symlink and
  `/private/var` alias bypass of the screenshots-dir refusal found by
  verification and closed with realpath on both sides.
- MAT-112: `capture-annotated` returns measured empty bands (`space`) per
  resolved target. The original elementFromPoint emptiness rule was killed by
  verification (four confirmed false-empty classes) and replaced with a
  geometric line-rect scan; a fifth miss (bare text nodes under an open
  ShadowRoot) survived the fix round and was closed by hand with the
  verifier's probe rerun and a permanent e2e case.
- Coordinate ladder: the macro flags `opaque` targets (canvas/iframe/img/
  video/embed/object) and the skill states the four-step escalation
  (selector, container arithmetic, disclosed within-capture inspection,
  import mode).
- MAT-113: `configure --video <WxH>|off`, runtime re-pinned to alpha.8,
  `fast-browser gif` (ffmpeg two-pass palettegen, name-confined), drift-exempt
  `gif-renderer` doctor check, `capturing-flows` skill with the PII rule.

## What shipped (runtime alpha.8)

- `saveVideo` config key consumed: `recordVideo` into `<outputDir>/videos` for
  launched contexts, plus protocol-level `recordVideo` through `connectOverCDP`
  so the extension relay records the real-Chrome tabs Fast Browser drives.
  `--save-video <WxH>` CLI flag added.
- The cli daemon deliberately does not record: its shutdown kills the encoder
  before the recorder finalizes, so a recording there is lost, not saved.
  Verified deterministically; wiring withdrawn rather than shipped broken.
- Docs state the delivered behavior (launched + relay + cdp-isolated record;
  daemon does not).

## Test results at ship

| Suite | Result |
| --- | --- |
| plugin unit + integration | 630 pass, 0 fail |
| plugin e2e: video, annotate, affordances | 1 + 4 + 5 pass, 0 fail, real runtime |
| fork tests/mcp save-video (chrome) | 3 pass, 0 fail; 121 neighbors green |
| fork tests/extension save-video (real Chrome + extension) | 1 pass |
| publish gate (`macro-hashes --check`) | passed before publish; alpha.7 recorded after |

## Live install on this machine

Setup ran for real against the published release: alpha.8 runtime downloaded
from GitHub and checksum-verified, launcher on PATH (`which fast-browser`
resolves), page-affordances and the space-capable capture-annotated installed,
doctor all green except `extension-loaded` (requires clicking reload in
chrome://extensions, a human step).

Two incidents during the live install, both resolved:

1. Setup without `--profile` reset the profile from `full` to `safe`, which
   also reset session settings. Restored with an explicit `--profile full`;
   config now matches the pre-incident backup plus `video: null`. This is live
   evidence for MAT-90 (setup should declare which fields each path may
   rewrite); noted on the ticket.
2. `~/.codex/config.toml` carried a stale unmanaged `[mcp_servers.fast_browser]`
   block from this session's earlier manual path repair, colliding with the
   managed block setup writes; Codex refused to load any config. Removed the
   stale block (backup: `~/.codex/config.toml.bak-20260730-shipfix`).

## Tickets

MAT-110, MAT-111, MAT-112, MAT-113 all Done. Still open in the project:
MAT-86/87/88 (shipped earlier, pending verification-based closure), MAT-89,
MAT-90 (now with live evidence), MAT-91.
