# Fast Browser release readiness

Generated after the local release suite passed. Nothing here was published.

## Identity

| Field | Value |
| --- | --- |
| mattstack commit | `f74f80aec2cef8f8ff5d7fe8045dc59dba6b7442` plus this report's commit |
| Playwright fork commit | `7af0ff16ddb30f46adccc1f837eba6a738e40c2a` (worktree clean) |
| Plugin version | 0.1.0-alpha.1 |
| Runtime version | 0.1.0-alpha.7 |
| Extension version | 0.2.4 |
| Protocol version | 2 |
| Extension ID | `bjlfojdaaanoliidngocnbcalhpfmlie` |
| License | MIT for the plugin source; Playwright artifacts remain Apache-2.0 |

## Artifacts

| Artifact | SHA-256 |
| --- | --- |
| `fast-browser-mcp-0.1.0-alpha.7.tar.gz` | `fa9fe1fda148d9e2604591fa8d31482e25252ab19f30e945b6b5fa2679c2eea7` |
| `fast-browser-extension-0.1.0-alpha.7.zip` | `764beb8d2adca7b50a34a648a98005bfbc845d253fb43d6ef90ad54e52b23ad5` |

## Test results

| Suite | Result |
| --- | --- |
| unit + integration (`npm test`) | 410 pass, 0 fail |
| direct MCP e2e (`npm run test:e2e`) | 4 pass, 0 fail |
| live two-host e2e | 44 pass (Task 3: CLAUDE-TEAM-5 and CODEX-SCALE-12, 4.8s) |
| `fast-browser doctor` | 18/18 against the real paired Chrome |
| `claude plugin validate` | passed |
| `git diff --check` | clean |

Live browser call against the real paired Chrome: `browser_snapshot` in 277ms.

## Migration and rollback

Exercised against the real installation, not fixtures.

- Dry-run matched the approved inventory: no unrelated MCP servers, rules,
  agents, or Codex config; `~/.playwright-mcp` never a deletion target; all
  legacy data actions copy-only; every removal backed up first; no token value
  in the report.
- Apply removed only the recognized legacy Claude registrations: the
  `browser-driver` agent and three `mattstack:` skill symlinks.
- Rollback restored every path with SHA-256 matching the backup manifest.
- Reapply was idempotent, and doctor stayed 18/18 throughout.
- All 77 legacy sessions remain in `~/.playwright-mcp` and were copied, not
  moved, into `~/.fast-browser`.

Two defects surfaced only by running this against the real machine.
`migrate` rejected `--source`, which made migration impossible on any machine
that had run setup, and `rollbackMigration` returned undefined, so a fully
successful rollback reported as a crash. Both are fixed.

## Scans

- `npm pack --dry-run` ships no tests, sessions, personal macros,
  `.local-dev`, or `node_modules`.
- No published file contains a maintainer absolute path or a literal token.
- LICENSE and THIRD_PARTY_NOTICES.md are both published.
- Notices are asserted against the runtime lock, so provenance cannot go stale
  silently again. It had gone stale: the notices named alpha.5 and an older
  source commit while the lock was at alpha.7, and a test pinned that stale
  commit literally, holding the rot in place instead of catching it.

## Published, with authorization

1. `m4ttheweric/playwright` branch `fast-browser-runtime` pushed.
2. Prerelease `fast-browser-v0.1.0-alpha.7` created at commit `7af0ff16` with
   both artifacts plus the release manifest. The locked URLs were then
   downloaded and verified byte-for-byte against the pinned SHA-256 values, and
   a clean install into a throwaway home succeeded from the bundled lock with
   no `--runtime-lock` override.
3. `m4ttheweric/mattstack` branch `fast-browser-dual-host` pushed (82 commits).
   Not merged to main.

4. `@mattstack/fast-browser@0.1.0-alpha.1` published to npm with public access
   under the `latest` tag. Verified from a directory with no checkout:
   `npx -y @mattstack/fast-browser@0.1.0-alpha.1 --version` resolves and runs.
   The earlier 403 was `npm org ls` lacking permission to enumerate the org,
   not a missing scope; the org exists and publish succeeded.

5. Both `main` branches fast-forwarded: `m4ttheweric/mattstack` to `e86559a`
   (83 commits) and `m4ttheweric/playwright` to `7af0ff16` (27 commits). Pushed
   to the remotes directly so the dirty local mattstack checkout was never
   touched; it still sits on the old main and needs a pull.

## Still not performed

Chrome Web Store submission only, which remains deliberately declined (see
below).

## Considered and deferred

Chrome Web Store submission is NOT a release step for this candidate. It was
evaluated and declined for now: the extension requests `debugger` together
with `<all_urls>`, which is the most heavily scrutinised permission pair on
the store; review latency would gate every alpha iteration; and store
auto-updates are incompatible with the pinned-lock integrity model, since
Chrome would own the extension bytes and `runtime-lock.json` could no longer
pin or verify them.

The extension ships instead as an unpacked load from
`~/.fast-browser/extension/current`, which setup installs and swaps in place.
Revisit the store only once the extension stops changing, and expect it to
require replacing artifact pinning with protocol version negotiation.

## Known gaps

- The extension still needs a manual load, and a manual reload per upgrade.
  Self-reload via `chrome.runtime.reload()` needs a runtime release.
- `extension-loaded` can report stale briefly after a real reload, because
  Chrome commits Secure Preferences lazily.
- Legacy `~/.fast-browser/extension/0.2.1` through `0.2.4` directories are not
  pruned automatically.
