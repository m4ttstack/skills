# Fast Browser Dual-Host Plugin and CLI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build one self-contained mattstack plugin and CLI that install, launch, diagnose, configure, migrate, and remove Fast Browser for Claude Code and Codex.

**Architecture:** A dependency-light Node.js 20+ ESM package owns shared configuration and process interfaces. Both plugin manifests launch one `fast-browser-mcp` wrapper; host adapters contain only marketplace, agent, instructions, and approval-policy differences; every home-directory mutation is recorded and reversible.

**Tech Stack:** Node.js 20+ ESM, built-in `node:test`, JSON, Markdown, TOML templates, MCP stdio, macOS `/usr/bin/security`, Claude Code CLI, Codex CLI.

## Global Constraints

- Work in an isolated mattstack worktree created after this plan set is committed.
- Do not modify or stage the user's dirty `skills/infra/local-app/SKILL.md` or `skills/workflow/matts-writing-style/SKILL.md`.
- Use `apply_patch` for source edits and explicit file paths for filesystem mutations.
- Support macOS and Google Chrome only.
- Use one plugin root for both host manifests and all shared skills.
- Require Node.js 20 or newer.
- Keep runtime startup offline and deterministic.
- Default to `safe`; require `--profile full` or an interactive choice for full parity.
- Session recording and macro-mining inputs are disabled in `safe` and enabled in `full`.
- Store no token in JSON, TOML, Markdown, a process argument, a log, or Git.
- Preserve unrelated Claude and Codex configuration exactly.
- Use `~/.fast-browser/` with directory mode `0700` and sensitive-file mode `0600`.
- Preserve Fast Browser data on ordinary uninstall; require `--purge-data` for deletion.
- Ship only the generic `page-recon` macro.
- Treat `browser_run_code_unsafe` as privileged and state-changing.
- Use version `0.1.0-alpha.1` for the first local candidate.

---

### Task 1: Scaffold the dual-host plugin and executable contract

**Files:**
- Create: `.claude-plugin/marketplace.json`
- Create: `.agents/plugins/marketplace.json`
- Create: `plugins/fast-browser/package.json`
- Create: `plugins/fast-browser/.claude-plugin/plugin.json`
- Create: `plugins/fast-browser/.codex-plugin/plugin.json`
- Create: `plugins/fast-browser/.mcp.json`
- Create: `plugins/fast-browser/adapters/codex/mcp.json`
- Create: `plugins/fast-browser/bin/fast-browser.mjs`
- Create: `plugins/fast-browser/bin/fast-browser-mcp.mjs`
- Create: `plugins/fast-browser/lib/cli/parse-args.mjs`
- Create: `plugins/fast-browser/lib/cli/main.mjs`
- Create: `plugins/fast-browser/tests/unit/parse-args.test.mjs`
- Create: `plugins/fast-browser/tests/unit/manifests.test.mjs`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: Claude and Codex documented plugin formats.
- Produces:
  `parseArgs(argv): CommandRequest`;
  `main(request, dependencies): Promise<number>`;
  CLI commands `setup`, `doctor`, `configure`, `migrate`, and `uninstall`; and
  MCP wrapper entry point `bin/fast-browser-mcp.mjs`.

- [ ] **Step 1: Create failing parser and manifest tests**

`parse-args.test.mjs`:

```js
import assert from 'node:assert/strict';
import test from 'node:test';
import { parseArgs } from '../../lib/cli/parse-args.mjs';

test('parses a two-host full setup', () => {
  assert.deepEqual(
    parseArgs(['setup', '--host', 'both', '--profile', 'full', '--source', '/tmp/mattstack']),
    {
      command: 'setup',
      hosts: ['claude', 'codex'],
      profile: 'full',
      source: '/tmp/mattstack',
      json: false,
      purgeData: false,
      dryRun: false,
      rollback: null,
      connection: null,
      recordSessions: null,
      retentionDays: null,
      runtimeLock: null,
    },
  );
});

test('defaults setup to detected hosts and safe profile', () => {
  assert.deepEqual(parseArgs(['setup']), {
    command: 'setup',
    hosts: [],
    profile: 'safe',
    source: 'm4ttheweric/mattstack',
    json: false,
    purgeData: false,
    dryRun: false,
    rollback: null,
    connection: null,
    recordSessions: null,
    retentionDays: null,
    runtimeLock: null,
  });
});

test('rejects unsupported platforms and flags through usage errors', () => {
  assert.throws(() => parseArgs(['setup', '--host', 'firefox']), /--host/);
  assert.throws(() => parseArgs(['uninstall', '--unknown']), /--unknown/);
});
```

`manifests.test.mjs` must load both plugin manifests and both marketplace files,
then assert:

```js
assert.equal(claude.name, 'fast-browser');
assert.equal(codex.name, 'fast-browser');
assert.equal(claude.version, codex.version);
assert.equal(codex.skills, './skills/');
assert.equal(codex.mcpServers, './adapters/codex/mcp.json');
assert.equal(claudeMarketplace.plugins[0].source, './plugins/fast-browser');
assert.deepEqual(codexMarketplace.plugins[0].source, {
  source: 'local',
  path: './plugins/fast-browser',
});
```

- [ ] **Step 2: Run the tests and verify the package is missing**

Run:

```bash
node --test plugins/fast-browser/tests/unit/parse-args.test.mjs plugins/fast-browser/tests/unit/manifests.test.mjs
```

Expected: FAIL with module/file-not-found errors.

- [ ] **Step 3: Create the package and CLI parser**

Use this package contract:

```json
{
  "name": "@mattstack/fast-browser",
  "version": "0.1.0-alpha.1",
  "description": "Fast Playwright browser automation for Claude Code and Codex",
  "type": "module",
  "private": true,
  "license": "UNLICENSED",
  "engines": {
    "node": ">=20"
  },
  "bin": {
    "fast-browser": "./bin/fast-browser.mjs"
  },
  "scripts": {
    "test": "node --test tests/unit/*.test.mjs tests/integration/*.test.mjs",
    "test:unit": "node --test tests/unit/*.test.mjs",
    "test:integration": "node --test tests/integration/*.test.mjs"
  }
}
```

`parseArgs` must support:

```js
{
  command: 'setup' | 'doctor' | 'configure' | 'migrate' | 'uninstall',
  hosts: Array<'claude' | 'codex'>,
  profile: 'safe' | 'full',
  source: string,
  json: boolean,
  purgeData: boolean,
  dryRun: boolean,
  rollback: string | null,
  connection: 'manual' | 'auto' | null,
  recordSessions: boolean | null,
  retentionDays: number | null,
  runtimeLock: string | null,
}
```

Do not add a generic flag library. Parse the small fixed grammar and throw
`UsageError` with the offending token.

Support `--dry-run` and `--rollback <manifest>` for `migrate`;
`--connection manual|auto`, `--record-sessions`, `--no-record-sessions`, and
`--retention-days <1..365>` for `configure`; and `--purge-data` for
`uninstall`. Support `--runtime-lock <release-json>` for local-candidate setup
and doctor without writing that path into plugin source. Reject each flag on
commands where it has no meaning.

- [ ] **Step 4: Create both manifests and MCP descriptors**

The Claude descriptor:

```json
{
  "mcpServers": {
    "fast-browser": {
      "command": "node",
      "args": ["${CLAUDE_PLUGIN_ROOT}/bin/fast-browser-mcp.mjs"]
    }
  }
}
```

The Codex descriptor:

```json
{
  "fast_browser": {
    "command": "node",
    "args": ["${PLUGIN_ROOT}/bin/fast-browser-mcp.mjs"]
  }
}
```

The Codex manifest points `mcpServers` to the Codex descriptor and both
manifests point skills to `./skills/`. Use `UNLICENSED` for the alpha; Plan 3
blocks public publication until Matt chooses an SPDX license.

Create both repository marketplace catalogs named `mattstack`, with one
`fast-browser` entry pointing to the same plugin directory.

- [ ] **Step 5: Wire the executable**

`bin/fast-browser.mjs`:

```js
#!/usr/bin/env node
import { main } from '../lib/cli/main.mjs';
import { parseArgs } from '../lib/cli/parse-args.mjs';

try {
  process.exitCode = await main(parseArgs(process.argv.slice(2)));
} catch (error) {
  process.stderr.write(`fast-browser: ${error.message}\n`);
  process.exitCode = error.exitCode ?? 1;
}
```

For now `main` returns `0` for `--help` and throws
`CommandNotImplementedError` for recognized commands. Later tasks replace each
branch without changing the parser result shape.

Add `.superpowers/` to `.gitignore`; do not ignore `.local-dev/superpowers/`.

- [ ] **Step 6: Run tests and host validators**

Run:

```bash
npm test --prefix plugins/fast-browser
claude plugin validate plugins/fast-browser
```

Expected: tests and Claude validation pass. Codex marketplace validation is
performed by adding the isolated worktree as a local marketplace in a temporary
Codex home during Task 5.

- [ ] **Step 7: Commit**

```bash
git add .claude-plugin .agents/plugins .gitignore plugins/fast-browser
git commit -m "feat(fast-browser): scaffold dual-host plugin"
```

### Task 2: Add portable paths, config schema, and atomic storage

**Files:**
- Create: `plugins/fast-browser/lib/core/paths.mjs`
- Create: `plugins/fast-browser/lib/core/config.mjs`
- Create: `plugins/fast-browser/lib/core/files.mjs`
- Create: `plugins/fast-browser/tests/unit/paths.test.mjs`
- Create: `plugins/fast-browser/tests/unit/config.test.mjs`

**Interfaces:**
- Consumes: `process.env`, `os.homedir()`, and the plugin root.
- Produces:
  `resolvePaths({ homeDir, pluginRoot }): FastBrowserPaths`;
  `defaultConfig(): FastBrowserConfig`;
  `parseConfig(value): FastBrowserConfig`;
  `loadConfig(paths): Promise<FastBrowserConfig>`;
  `saveConfig(paths, config): Promise<void>`; and
  `ensurePrivateDirectory(path): Promise<void>`.

- [ ] **Step 1: Write failing path and config tests**

Use a synthetic home, never the real home:

```js
test('resolves every mutable path below the supplied home', () => {
  const paths = resolvePaths({ homeDir: '/tmp/fb-home', pluginRoot: '/plugin' });
  assert.equal(paths.dataDir, '/tmp/fb-home/.fast-browser');
  assert.equal(paths.configFile, '/tmp/fb-home/.fast-browser/config.json');
  assert.equal(paths.macrosDir, '/tmp/fb-home/.fast-browser/macros');
  assert.equal(paths.sessionsDir, '/tmp/fb-home/.fast-browser/sessions');
  assert.equal(paths.runtimeDir, '/tmp/fb-home/.fast-browser/runtime');
  assert.equal(paths.pluginRoot, '/plugin');
});

test('safe config contains no secret and disables recording', () => {
  assert.deepEqual(defaultConfig(), {
    schemaVersion: 1,
    productVersion: '0.1.0-alpha.1',
    profile: 'safe',
    hosts: { claude: false, codex: false },
    connection: { mode: 'manual' },
    sessions: { enabled: false, retentionDays: 30 },
    runtime: { version: null, sha256: null, sourceCommit: null },
    managed: { files: [], blocks: [] },
  });
});
```

Add tests for invalid schema version, unknown profile, invalid retention, atomic
rewrite, and modes `0700`/`0600`.

- [ ] **Step 2: Run and verify failure**

Run:

```bash
npm run test:unit --prefix plugins/fast-browser
```

Expected: FAIL because the core modules do not exist.

- [ ] **Step 3: Implement paths and validation**

Use `path.join(homeDir, '.fast-browser')`; never expand `~` manually. Return:

```js
{
  homeDir,
  pluginRoot,
  dataDir,
  configFile,
  runtimeDir,
  extensionDir,
  macrosDir,
  sessionsDir,
  archiveDir,
  backupsDir,
  macroFailuresFile,
}
```

`parseConfig` must build a new object containing only supported fields and
throw `ConfigError` for invalid types or values. It must not pass through
unknown keys.

- [ ] **Step 4: Implement private and atomic writes**

`saveConfig`:

```js
export async function saveConfig(paths, config) {
  const parsed = parseConfig(config);
  await ensurePrivateDirectory(paths.dataDir);
  const temporary = path.join(
    paths.dataDir,
    `.config.json.${process.pid}.${crypto.randomUUID()}.tmp`,
  );
  await fs.writeFile(temporary, JSON.stringify(parsed, null, 2) + '\n', { mode: 0o600 });
  await fs.chmod(temporary, 0o600);
  await fs.rename(temporary, paths.configFile);
}
```

`ensurePrivateDirectory` creates recursively and always applies mode `0700`.

- [ ] **Step 5: Run tests and commit**

Run:

```bash
npm run test:unit --prefix plugins/fast-browser
```

Expected: PASS.

```bash
git add plugins/fast-browser/lib/core plugins/fast-browser/tests/unit
git commit -m "feat(fast-browser): add private configuration store"
```

### Task 3: Install, verify, and launch the pinned runtime

**Files:**
- Create: `plugins/fast-browser/runtime-lock.json`
- Create: `plugins/fast-browser/lib/runtime/lock.mjs`
- Create: `plugins/fast-browser/lib/runtime/install.mjs`
- Create: `plugins/fast-browser/lib/runtime/launch.mjs`
- Create: `plugins/fast-browser/lib/extension/install.mjs`
- Create: `plugins/fast-browser/lib/extension/detect.mjs`
- Create: `plugins/fast-browser/tests/unit/runtime-lock.test.mjs`
- Create: `plugins/fast-browser/tests/integration/runtime-install.test.mjs`
- Create: `plugins/fast-browser/tests/integration/extension-install.test.mjs`
- Modify: `plugins/fast-browser/bin/fast-browser-mcp.mjs`

**Interfaces:**
- Consumes: Plan 1 release JSON and a Fetch-compatible `fetch`.
- Produces:
  `parseRuntimeLock(value): RuntimeLock`;
  `loadRuntimeLock({ bundledPath, overridePath }): Promise<RuntimeLock>`;
  `installRuntime({ lock, paths, fetch }): Promise<InstalledRuntime>`;
  `installExtension({ lock, paths, fetch }): Promise<InstalledExtension>`;
  `detectChromeExtension({ extensionId, chromeUserDataDir }): Promise<ExtensionDetection>`;
  `runtimeArgs({ config, paths, lock }): string[]`; and
  `launchRuntime({ config, paths, lock, readToken, spawn }): Promise<never>`.

- [ ] **Step 1: Write failing lock and installer tests**

Use a local HTTP server that returns a tiny test tarball and count requests.
Assert:

```js
assert.deepEqual(parseRuntimeLock(lock), {
  schemaVersion: 1,
  productVersion: '0.1.0-alpha.1',
  sourceCommit: '0123456789abcdef',
  protocolVersion: 2,
  runtime: {
    url: 'http://127.0.0.1:PORT/runtime.tar.gz',
    file: 'fast-browser-mcp-0.1.0-alpha.1.tar.gz',
    sha256,
    node: '>=20',
  },
  extension: {
    url: 'http://127.0.0.1:PORT/extension.zip',
    file: 'fast-browser-extension-0.1.0-alpha.1.zip',
    sha256: extensionSha256,
    id: 'abcdefghijklmnopabcdefghijklmnop',
    version: '0.2.1',
  },
});
```

Test checksum mismatch, interrupted download, traversal entry rejection, second
install without a second download, extension zip traversal rejection, Chrome
profile detection in both `Default` and `Profile <N>`, and a launcher argument
snapshot.

The full-profile argument expectation is:

```js
[
  '--extension',
  '--extension-id=abcdefghijklmnopabcdefghijklmnop',
  '--snapshot-mode=none',
  '--timeout-settle=200',
  `--output-dir=${paths.dataDir}`,
  '--save-session',
]
```

Safe omits `--save-session`.

- [ ] **Step 2: Run and verify failure**

Run:

```bash
npm test --prefix plugins/fast-browser
```

Expected: FAIL because runtime modules and lock do not exist.

- [ ] **Step 3: Implement lock parsing and checksum-addressed installation**

`runtime-lock.json` uses the Plan 1 schema plus immutable artifact URLs. During
normal operation, the parser accepts immutable `https:` URLs only. An explicit
local `--runtime-lock` override accepts a Plan 1 release JSON whose artifact
filenames are resolved against that JSON's directory. The resolved local URLs
exist only in memory and are never written to plugin source or user config.
Tests may also use `http://127.0.0.1` or `http://localhost` fixtures.

Download to `runtime/<version>/.download`, hash while streaming, compare with
`crypto.timingSafeEqual`, then extract into
`runtime/<version>/.staging-<uuid>`. List the tar archive before extraction and
reject absolute paths or any segment equal to `..`. Rename the completed
directory atomically and write `installed.json` mode `0600`.

`installExtension` follows the same download/checksum/staging/rename transaction
under `extension/<version>/unpacked/`. List zip entries before extraction and
reject absolute paths, `..` segments, symlinks, and entries outside the
`unpacked` root. Confirm the extracted `manifest.json` key derives to the locked
extension ID before rename.

`detectChromeExtension` checks the exact locked ID in Chrome's `Default` and
`Profile <N>` `Extensions/` directories and Preferences files. It returns only
profile name, installed boolean, and manifest version; it never reads extension
local storage.

- [ ] **Step 4: Implement the MCP launcher**

`launchRuntime` resolves:

```text
~/.fast-browser/runtime/<version>/fast-browser-mcp/cli.cjs
```

It validates Node 20+, builds the fixed arguments, obtains a Keychain token only
when `connection.mode === 'auto'`, and spawns:

```js
spawn(process.execPath, [runtimeCli, ...args], {
  stdio: 'inherit',
  shell: false,
  env: token
    ? { ...process.env, PLAYWRIGHT_MCP_EXTENSION_TOKEN: token }
    : process.env,
});
```

The wrapper must not print the environment. Map `ENOENT`, checksum state, and
nonzero exit to one-line errors that name `fast-browser doctor`.

- [ ] **Step 5: Run tests and an extracted-runtime help smoke**

Run:

```bash
npm test --prefix plugins/fast-browser
node plugins/fast-browser/bin/fast-browser-mcp.mjs --help
```

Expected: tests pass. Before setup, the wrapper exits nonzero with an actionable
missing-runtime message and never attempts a download.

- [ ] **Step 6: Commit**

```bash
git add plugins/fast-browser/runtime-lock.json plugins/fast-browser/lib/runtime plugins/fast-browser/lib/extension plugins/fast-browser/bin/fast-browser-mcp.mjs plugins/fast-browser/tests
git commit -m "feat(fast-browser): install and launch pinned runtime"
```

### Task 4: Add macOS Keychain pairing without secret leakage

**Files:**
- Create: `plugins/fast-browser/lib/keychain/keychain.mjs`
- Create: `plugins/fast-browser/lib/keychain/pair.mjs`
- Create: `plugins/fast-browser/tests/unit/keychain.test.mjs`
- Create: `plugins/fast-browser/tests/integration/keychain-redaction.test.mjs`

**Interfaces:**
- Consumes: `/usr/bin/security` and injected `spawn`.
- Produces:
  `hasToken(deps): Promise<boolean>`;
  `readToken(deps): Promise<string | null>`;
  `writeTokenFromPrompt(deps): Promise<void>`;
  `writeMigratedToken(token, deps): Promise<void>`; and
  `deleteToken(deps): Promise<boolean>`.

- [ ] **Step 1: Write failing command and redaction tests**

Assert exact non-secret arguments:

```js
assert.deepEqual(calls[0].args, [
  'find-generic-password',
  '-s', 'dev.mattstack.fast-browser',
  '-a', 'chrome-extension',
  '-w',
]);
```

For writes, assert `-w` is the final argument and the secret appears only in
captured stdin:

```js
assert.deepEqual(call.args, [
  'add-generic-password',
  '-U',
  '-s', 'dev.mattstack.fast-browser',
  '-a', 'chrome-extension',
  '-w',
]);
assert.equal(call.stdin, 'secret-value\n');
assert.doesNotMatch(JSON.stringify(call.args), /secret-value/);
```

Test not-found exit 44, delete idempotence, whitespace trimming on read, and
that thrown errors redact both the supplied and returned token.

- [ ] **Step 2: Run and verify failure**

Run:

```bash
npm run test:unit --prefix plugins/fast-browser
```

Expected: FAIL because the Keychain modules do not exist.

- [ ] **Step 3: Implement the Keychain adapter**

Use constants:

```js
export const KEYCHAIN_SERVICE = 'dev.mattstack.fast-browser';
export const KEYCHAIN_ACCOUNT = 'chrome-extension';
```

`writeTokenFromPrompt` spawns `/usr/bin/security add-generic-password ... -w`
with inherited stdin and stderr so `security` owns the no-echo prompt.

`writeMigratedToken` spawns the same command with piped stdin and writes
`${token}\n`; it never adds the token to args. `readToken` captures stdout,
trims exactly one terminal newline, and never includes stdout in an error.

- [ ] **Step 4: Add the pairing flow**

`pairAutoConnect` prints:

```text
1. Open the Fast Browser extension status page.
2. Copy the raw reconnect token.
3. Paste it into the secure macOS Keychain prompt below.
```

Then it calls `writeTokenFromPrompt`, verifies `hasToken`, and updates config to
`connection: { mode: 'auto' }`. Manual mode deletes no existing Keychain item
until the user explicitly confirms a mode change.

- [ ] **Step 5: Run redaction tests and commit**

Run:

```bash
npm test --prefix plugins/fast-browser
```

Expected: PASS and test output contains no synthetic token.

```bash
git add plugins/fast-browser/lib/keychain plugins/fast-browser/tests
git commit -m "feat(fast-browser): store pairing token in Keychain"
```

### Task 5: Implement Claude Code and Codex installation adapters

**Files:**
- Create: `plugins/fast-browser/lib/core/process.mjs`
- Create: `plugins/fast-browser/lib/hosts/detect.mjs`
- Create: `plugins/fast-browser/lib/hosts/claude.mjs`
- Create: `plugins/fast-browser/lib/hosts/codex.mjs`
- Create: `plugins/fast-browser/tests/unit/process.test.mjs`
- Create: `plugins/fast-browser/tests/unit/hosts.test.mjs`
- Create: `plugins/fast-browser/tests/integration/plugin-install.test.mjs`

**Interfaces:**
- Consumes: injected command runner and marketplace source.
- Produces:
  `run(command, args, options): Promise<RunResult>`;
  `detectHosts(deps): Promise<Array<'claude' | 'codex'>>`;
  `installClaude({ source, run }): Promise<HostInstallResult>`;
  `uninstallClaude({ run }): Promise<HostInstallResult>`;
  `installCodex({ source, run }): Promise<HostInstallResult>`; and
  `uninstallCodex({ run }): Promise<HostInstallResult>`.

- [ ] **Step 1: Write exact-command adapter tests**

For Claude:

```js
assert.deepEqual(calls, [
  ['claude', ['plugin', 'marketplace', 'add', source, '--scope', 'user', '--sparse', '.claude-plugin', 'plugins/fast-browser']],
  ['claude', ['plugin', 'install', 'fast-browser@mattstack', '--scope', 'user']],
]);
```

For Codex:

```js
assert.deepEqual(calls, [
  ['codex', ['plugin', 'marketplace', 'add', source, '--sparse', '.agents/plugins', '--sparse', 'plugins/fast-browser', '--json']],
  ['codex', ['plugin', 'add', 'fast-browser@mattstack', '--json']],
]);
```

Tests must cover already-installed output, marketplace refresh/update, partial
failure, uninstall, missing CLI, and stderr redaction.

- [ ] **Step 2: Run and verify failure**

Run:

```bash
npm run test:unit --prefix plugins/fast-browser
```

Expected: FAIL because host modules do not exist.

- [ ] **Step 3: Implement the non-shell process runner**

Use `spawn(command, args, { shell: false })`, collect bounded stdout/stderr, and
return:

```js
{
  command,
  args,
  exitCode,
  stdout,
  stderr,
}
```

Cap each captured stream at 1 MiB and indicate truncation. Never include
environment values in results.

- [ ] **Step 4: Implement idempotent host adapters**

Before adding, query:

```text
claude plugin list
claude plugin marketplace list
codex plugin list --available --json
codex plugin marketplace list --json
```

If the source exists, refresh it (`marketplace update mattstack` for Claude,
`marketplace upgrade mattstack` for Codex). If the same plugin version is
installed, return `changed: false`. Replace only the `fast-browser@mattstack`
installation when the version differs.

- [ ] **Step 5: Validate the real local marketplace in isolated config homes**

Use temporary directories and copies of only the minimum host config needed.
Run marketplace add/list and plugin validation without installing into Matt's
real home. Assert both hosts resolve `fast-browser` from the same source
directory.

- [ ] **Step 6: Run tests and commit**

Run:

```bash
npm test --prefix plugins/fast-browser
claude plugin validate plugins/fast-browser
```

Expected: PASS.

```bash
git add plugins/fast-browser/lib/core/process.mjs plugins/fast-browser/lib/hosts plugins/fast-browser/tests
git commit -m "feat(fast-browser): install both host adapters"
```

### Task 6: Add profile routing, browser-driver agents, and Codex tool policy

**Files:**
- Create: `plugins/fast-browser/agents/browser-driver.md`
- Create: `plugins/fast-browser/templates/codex/browser_driver.toml`
- Create: `plugins/fast-browser/templates/routing/claude/fast-browser-routing.md`
- Create: `plugins/fast-browser/templates/routing/claude/fast-browser-verification-consent.md`
- Create: `plugins/fast-browser/templates/routing/codex/fast-browser.md`
- Create: `plugins/fast-browser/lib/hosts/managed-block.mjs`
- Create: `plugins/fast-browser/lib/hosts/codex-agent.mjs`
- Create: `plugins/fast-browser/lib/hosts/routing.mjs`
- Create: `plugins/fast-browser/tests/unit/managed-block.test.mjs`
- Create: `plugins/fast-browser/tests/unit/codex-agent.test.mjs`
- Create: `plugins/fast-browser/tests/unit/routing.test.mjs`

**Interfaces:**
- Consumes: `FastBrowserPaths`, profile, and exact templates.
- Produces:
  `upsertManagedBlock(text, { id, body }): string`;
  `removeManagedBlock(text, id): string`;
  `renderCodexAgent({ usePreferredModel }): string`;
  `installRouting({ profile, paths }): Promise<ManagedState>`;
  `removeRouting({ paths, managedState }): Promise<void>`.

- [ ] **Step 1: Write failing managed-content tests**

Use markers:

```text
<!-- fast-browser:start routing-v1 -->
<!-- fast-browser:end routing-v1 -->
```

Assert insertion, replacement, removal, preservation of surrounding bytes,
newline stability, duplicate-marker rejection, and selection of
`AGENTS.override.md` when present.

Assert full Codex policy inserts:

```toml
# fast-browser:start mcp-policy-v1
[plugins."fast-browser@mattstack".mcp_servers.fast_browser]
enabled = true
default_tools_approval_mode = "approve"

[plugins."fast-browser@mattstack".mcp_servers.fast_browser.tools.browser_run_code_unsafe]
approval_mode = "approve"
# fast-browser:end mcp-policy-v1
```

Safe uses `default_tools_approval_mode = "writes"` and
`browser_run_code_unsafe = "prompt"`.

- [ ] **Step 2: Run and verify failure**

Run:

```bash
npm run test:unit --prefix plugins/fast-browser
```

Expected: FAIL because routing modules do not exist.

- [ ] **Step 3: Create portable agent templates**

The Claude agent frontmatter:

```yaml
---
name: browser-driver
description: Drives a delegated multi-step browser task through Fast Browser and returns only the distilled result.
model: sonnet
effort: medium
---
```

The Codex template uses a literal `{{MODEL_LINE}}` token:

```toml
name = "browser_driver"
description = "Drive multi-step browser tasks through Fast Browser and return only distilled results."
{{MODEL_LINE}}
model_reasoning_effort = "medium"
developer_instructions = """
Use only the Fast Browser MCP browser tools for the delegated task.
Check ~/.fast-browser/macros/MACROS.md first.
Return the requested result and at most one sentence of caveat; never return page dumps or click narration.
"""
```

`renderCodexAgent({ usePreferredModel: true })` replaces the token with
`model = "gpt-5.6-terra"`; false removes the whole line. Unit tests assert no
template token remains in either output. Setup selects the preferred line for
Codex CLI `>=0.145.0`; older or unparsable versions inherit the user's model.
Doctor performs a browser-driver smoke after installation and, if Codex rejects
the preferred model, rewrites only the owned agent file without the model line
and retries once.

Both bodies must encode macro-first behavior, one initial scout, batched
`browser_run_code_unsafe`, targeted reads, twice-failed recovery, real-Chrome
boundaries, and no login on the user's behalf.

- [ ] **Step 4: Create safe and full routing templates**

Safe installs the agent but no global Playwright-first rule.

Full Claude routing uses two dedicated files under `~/.claude/rules/` and
forbids fallback to Claude-in-Chrome unless explicitly requested.

Full Codex routing is inserted into the active global AGENTS file and states
that Fast Browser takes precedence over `browser-use:browser` for ordinary
browser-driving requests. It explicitly requests browser-driver delegation for
multi-step work, satisfying Codex's delegation gate.

- [ ] **Step 5: Implement reversible installation**

Write dedicated Claude files atomically. Copy the Codex agent atomically to
`~/.codex/agents/browser_driver.toml`. Record SHA-256 and target path for every
created file. For existing user files, refuse to overwrite a non-owned file and
report the conflict.

For global Codex Markdown and TOML config, replace only Fast Browser marker
blocks and preserve all other bytes.

- [ ] **Step 6: Run tests and commit**

Run:

```bash
npm test --prefix plugins/fast-browser
```

Expected: PASS.

```bash
git add plugins/fast-browser/agents plugins/fast-browser/templates plugins/fast-browser/lib/hosts plugins/fast-browser/tests
git commit -m "feat(fast-browser): add parity routing and agents"
```

### Task 7: Port and harden the shared browser skills and macros

**Files:**
- Move: `skills/browser/fast-browsing/SKILL.md` → `plugins/fast-browser/skills/fast-browsing/SKILL.md`
- Move: `skills/browser/browser-macros/SKILL.md` → `plugins/fast-browser/skills/browser-macros/SKILL.md`
- Move: `skills/browser/browser-macros/MACROS.md` → `plugins/fast-browser/skills/browser-macros/MACROS.md`
- Move: `skills/browser/mine-macros/SKILL.md` → `plugins/fast-browser/skills/mine-macros/SKILL.md`
- Move: `skills/browser/mine-macros/rejected.md` → `plugins/fast-browser/skills/mine-macros/rejected.md`
- Create: `plugins/fast-browser/builtins/macros/page-recon.js`
- Create: `plugins/fast-browser/lib/macros/install.mjs`
- Create: `plugins/fast-browser/lib/sessions/retention.mjs`
- Create compatibility links below: `skills/browser/`
- Create: `plugins/fast-browser/tests/unit/skills.test.mjs`
- Create: `plugins/fast-browser/tests/unit/macros.test.mjs`
- Create: `plugins/fast-browser/tests/unit/retention.test.mjs`

**Interfaces:**
- Consumes: `~/.fast-browser/macros/` and
  `browser_run_code_unsafe({ filename, args })`.
- Produces:
  `installBuiltinMacros(paths): Promise<void>`;
  `pruneSessions({ paths, now, retentionDays }): Promise<PruneResult>`; and
  three portable plugin skills.

- [ ] **Step 1: Write failing portability and macro tests**

Scan all packaged Markdown and JavaScript:

```js
for (const file of packagedSkillAndMacroFiles) {
  const text = await fs.readFile(file, 'utf8');
  assert.doesNotMatch(text, /\/Users\/matt|~\/\.claude|~\/\.codex|~\/\.playwright-mcp/);
  assert.doesNotMatch(text, /order-wizard|pw-bench/);
}
```

Evaluate `page-recon.js` with a fake page and assert:

```js
assert.deepEqual(await macro(fakePage, { maxLinks: 3 }), {
  url: 'https://example.test/',
  title: 'Example',
  headings: ['Welcome'],
  links: [{ name: 'Continue', href: '/next' }],
});
```

Test that built-ins are copied only when absent and never overwrite a
user-edited macro.

Create session/archive fixtures on both sides of a 30-day cutoff. Assert
`pruneSessions` deletes only entries inside the exact Fast Browser sessions and
archive roots whose modification time is older than the cutoff, never follows a
symlink, and returns the paths and byte count removed.

- [ ] **Step 2: Run and verify failure**

Run:

```bash
npm run test:unit --prefix plugins/fast-browser
```

Expected: FAIL because the packaged skills and macro do not exist.

- [ ] **Step 3: Move and rewrite the skills**

Replace all host-specific references with:

```text
~/.fast-browser/macros/MACROS.md
~/.fast-browser/macro-failures.md
~/.fast-browser/sessions/
~/.fast-browser/archive/
```

Keep the macro-first, scout-once, batch, targeted-read, two-failure recovery,
distilled-return, and per-macro approval contracts. Session mining must exit
with a clear message when recording is disabled.

- [ ] **Step 4: Implement `page-recon`**

The macro signature is:

```js
async (page, args) => {
  const { maxLinks = 10 } = args || {};
  const headings = await page.getByRole('heading').allTextContents();
  const links = await page.getByRole('link').evaluateAll((nodes, limit) =>
    nodes.slice(0, limit).map(node => ({
      name: (node.textContent || '').trim(),
      href: node.getAttribute('href') || '',
    })), maxLinks);
  return {
    url: page.url(),
    title: await page.title(),
    headings: headings.slice(0, 10),
    links,
  };
}
```

Add one `MACROS.md` entry with `maxLinks`, the stable data-directory path, and
status `built-in`.

- [ ] **Step 5: Add transition links**

Create repository-relative symlinks at the three old skill directories pointing
to the new plugin skill directories. Verify Matt's existing
`~/.claude/skills/mattstack:*` symlinks still resolve through the transition
links. The packaged plugin must contain real files, not links outside its root.

- [ ] **Step 6: Implement retention without broad deletion**

Resolve and realpath the sessions and archive roots once. Enumerate only direct
`session-*` directories and archived session directories. Refuse a candidate
whose realpath escapes its root or is a symlink. Remove an eligible directory
only after checking its explicit path and modification time.

Safe profile never records sessions. Full profile calls `pruneSessions` after a
successful setup and after macro mining, using the configured 30-day default.
Doctor reports stale bytes but does not delete them.

- [ ] **Step 7: Run tests and commit**

Run:

```bash
npm test --prefix plugins/fast-browser
claude plugin validate plugins/fast-browser
```

Expected: PASS and the forbidden-path scan is empty.

```bash
git add skills/browser plugins/fast-browser/skills plugins/fast-browser/builtins plugins/fast-browser/lib/macros plugins/fast-browser/lib/sessions plugins/fast-browser/tests
git commit -m "feat(fast-browser): share portable browser skills"
```

### Task 8: Add transactional legacy migration and rollback

**Files:**
- Create: `plugins/fast-browser/lib/migration/inventory.mjs`
- Create: `plugins/fast-browser/lib/migration/backup.mjs`
- Create: `plugins/fast-browser/lib/migration/import-data.mjs`
- Create: `plugins/fast-browser/lib/migration/apply.mjs`
- Create: `plugins/fast-browser/lib/migration/rollback.mjs`
- Create: `plugins/fast-browser/tests/unit/migration.test.mjs`
- Create: `plugins/fast-browser/tests/fixtures/legacy-home/`

**Interfaces:**
- Consumes: a supplied home directory, current config parsers, and Keychain
  writer.
- Produces:
  `inventoryLegacy(paths): Promise<LegacyInventory>`;
  `createMigrationBackup(inventory, paths): Promise<BackupManifest>`;
  `importLegacyData(...): Promise<ImportResult>`;
  `applyMigration(...): Promise<MigrationResult>`; and
  `rollbackMigration(manifest, dependencies): Promise<void>`.

- [ ] **Step 1: Build a synthetic legacy-home fixture and failing tests**

The fixture includes:

- a Claude JSON file with unrelated MCP entries plus recognized `playwright`;
- the two recognized rule files;
- a recognized browser-driver agent;
- mattstack browser skill symlinks;
- `.playwright-mcp/macros/MACROS.md` containing a synthetic `/Users/example`
  path;
- one personal macro, failure record, session, and archive entry; and
- an unrelated `.playwright-mcp/keep.txt`.

Tests assert inventory ignores unrelated entries, backup mode is `0600`, imports
rewrite macro paths, source data remains, apply removes only recognized host
entries after a supplied verification callback succeeds, and rollback restores
byte-identical files.

- [ ] **Step 2: Run and verify failure**

Run:

```bash
npm run test:unit --prefix plugins/fast-browser
```

Expected: FAIL because migration modules do not exist.

- [ ] **Step 3: Implement inventory and backup**

Identify resources by exact command, known path, or Fast Browser marker—not by
broad filename pattern. The backup manifest records:

```js
{
  schemaVersion: 1,
  createdAt,
  homeDir,
  files: [{ path, sha256, backupPath, mode }],
  jsonEdits: [{ path, pointer, before }],
  symlinks: [{ path, target }],
}
```

Do not include the legacy token value in JSON. If found, keep it only in memory
long enough to call `writeMigratedToken`.

- [ ] **Step 4: Implement copy-first import**

Copy macros, failure records, sessions, and archive into `~/.fast-browser/`
without deleting sources. Rewrite only `Script:` paths in imported `MACROS.md`.
Keep Matt's personal macros local; only packaged built-ins remain in Git.

Use collision names `<name>.legacy-<short-sha>.js` rather than overwrite
different existing data.

- [ ] **Step 5: Implement apply and rollback**

`applyMigration` order:

1. inventory;
2. backup;
3. import data;
4. migrate token to Keychain;
5. install new adapters and routing;
6. call `verify()`;
7. remove recognized legacy registration and symlinks only on success; and
8. write `rollback.json` plus a printable
   `fast-browser migrate --rollback <manifest>` command.

On any error before step 7, keep the legacy setup active. Rollback verifies
current hashes before replacing files and stops on an unrelated post-migration
edit.

- [ ] **Step 6: Run tests and commit**

Run:

```bash
npm test --prefix plugins/fast-browser
```

Expected: PASS.

```bash
git add plugins/fast-browser/lib/migration plugins/fast-browser/tests
git commit -m "feat(fast-browser): add reversible legacy migration"
```

### Task 9: Implement setup, doctor, configure, and uninstall orchestration

**Files:**
- Create: `plugins/fast-browser/lib/commands/setup.mjs`
- Create: `plugins/fast-browser/lib/commands/doctor.mjs`
- Create: `plugins/fast-browser/lib/commands/configure.mjs`
- Create: `plugins/fast-browser/lib/commands/migrate.mjs`
- Create: `plugins/fast-browser/lib/commands/uninstall.mjs`
- Create: `plugins/fast-browser/lib/doctor/checks.mjs`
- Modify: `plugins/fast-browser/lib/cli/main.mjs`
- Create: `plugins/fast-browser/tests/unit/commands.test.mjs`
- Create: `plugins/fast-browser/tests/integration/lifecycle.test.mjs`

**Interfaces:**
- Consumes: all prior Plan 2 interfaces.
- Produces:
  `setup(request, deps): Promise<SetupReport>`;
  `doctor(request, deps): Promise<DoctorReport>`;
  `configure(request, deps): Promise<ConfigureReport>`;
  `migrate(request, deps): Promise<MigrationReport>`; and
  `uninstall(request, deps): Promise<UninstallReport>`.

- [ ] **Step 1: Write failing lifecycle tests**

Use injected fake host adapters, runtime installer, Keychain, and filesystem.
Assert the setup call order:

```js
assert.deepEqual(events, [
  'check-platform',
  'detect-hosts',
  'ensure-data-dirs',
  'install-runtime',
  'install-extension-artifact',
  'install-claude',
  'install-codex',
  'install-builtins',
  'prune-sessions',
  'install-routing',
  'save-config',
  'doctor',
]);
```

Assert a second setup changes nothing; failed doctor keeps legacy resources;
configure safe→full changes recording, routing, and approval policy;
`--connection auto` invokes secure pairing; explicit recording and retention
flags override profile defaults; migrate dry-run performs no writes; rollback
routes to the exact manifest; ordinary uninstall retains data; purge requires
an explicit confirmation dependency.

- [ ] **Step 2: Define the stable doctor schema**

Tests expect:

```js
{
  schemaVersion: 1,
  ok: true,
  profile: 'full',
  checks: [
    {
      id: 'runtime-checksum',
      status: 'pass',
      message: 'Runtime 0.1.0-alpha.1 matches its lock.',
      remediation: null,
    },
  ],
}
```

Required IDs:

```text
platform
node
chrome
claude-cli
codex-cli
claude-plugin
codex-plugin
claude-routing
codex-routing
browser-driver
runtime-checksum
extension-artifact
extension-installed
pairing
data-permissions
mcp-handshake
tool-contract
```

No check may return or print a Keychain value.

- [ ] **Step 3: Run and verify failure**

Run:

```bash
npm test --prefix plugins/fast-browser
```

Expected: FAIL because command modules do not exist.

- [ ] **Step 4: Implement command orchestration**

`main` dispatches commands and renders either concise human output or JSON.
Human setup output ends with:

```text
Fast Browser is configured for: Claude Code, Codex
Profile: full
Chrome extension: manual installation required at <path>
Next: load the extension, then run `fast-browser doctor`
```

Setup never silently selects `full`. In non-interactive mode with no explicit
host, fail with the detected hosts and the exact `--host` command.

`configure` applies only explicitly supplied connection/recording/retention
flags after the selected profile defaults, validates retention in `1..365`,
prunes eligible sessions only after saving a valid full-profile config, and
never deletes a Keychain item without confirmation.

`migrate --dry-run` returns inventory and proposed exact mutations without
creating a backup or importing data. `migrate --rollback <manifest>` bypasses
inventory and invokes only `rollbackMigration` for that resolved manifest.

- [ ] **Step 5: Implement doctor and uninstall safety**

MCP handshake spawns the runtime, sends MCP `initialize` and `tools/list`, and
closes it with a 10-second timeout. Tool contract verifies
`browser_run_code_unsafe` annotations and required browser tools.

Uninstall resolves exact managed targets from config, verifies they remain
owned, removes selected host registrations, routing, and agent files, and keeps
`~/.fast-browser/`. Purge accepts only the exact resolved data directory and
refuses `/`, the home directory, an empty path, or a symlink.

- [ ] **Step 6: Run tests and commit**

Run:

```bash
npm test --prefix plugins/fast-browser
```

Expected: PASS.

```bash
git add plugins/fast-browser/lib/commands plugins/fast-browser/lib/doctor plugins/fast-browser/lib/cli/main.mjs plugins/fast-browser/tests
git commit -m "feat(fast-browser): orchestrate setup and lifecycle"
```

### Task 10: Document, validate, and package the plugin candidate

**Files:**
- Create: `plugins/fast-browser/README.md`
- Create: `plugins/fast-browser/SECURITY.md`
- Create: `plugins/fast-browser/THIRD_PARTY_NOTICES.md`
- Create: `plugins/fast-browser/tests/integration/package.test.mjs`
- Modify: `README.md`
- Modify: `.claude-plugin/marketplace.json`
- Modify: `.agents/plugins/marketplace.json`

**Interfaces:**
- Consumes: the complete plugin and local Plan 1 artifact lock.
- Produces: a validated `npm pack` candidate and source-install instructions.

- [ ] **Step 1: Write the package-hygiene test**

Pack to a temporary directory, list the tarball, and assert:

```js
assert.equal(entries.some(entry => entry.includes('.superpowers/')), false);
assert.equal(entries.some(entry => entry.includes('.local-dev/')), false);
assert.equal(entries.some(entry => entry.includes('/Users/matt')), false);
assert.equal(entries.some(entry => entry.includes('.playwright-mcp')), false);
assert.equal(entries.some(entry => entry.endsWith('skills/fast-browsing/SKILL.md')), true);
assert.equal(entries.some(entry => entry.endsWith('.claude-plugin/plugin.json')), true);
assert.equal(entries.some(entry => entry.endsWith('.codex-plugin/plugin.json')), true);
```

Extract text files and scan for:

```text
/Users/matt
PLAYWRIGHT_MCP_EXTENSION_TOKEN=
order-wizard
pw-bench
```

- [ ] **Step 2: Run and verify documentation/package failure**

Run:

```bash
npm test --prefix plugins/fast-browser
```

Expected: FAIL because required docs/notices are missing or package contents are
not constrained.

- [ ] **Step 3: Write installation, privacy, and troubleshooting docs**

README must cover:

- `npx @mattstack/fast-browser setup`;
- local source setup with `--source /path/to/mattstack`;
- safe versus full behavior;
- developer-mode extension loading;
- `doctor --json`;
- recorded-session sensitivity;
- migration and rollback;
- ordinary uninstall versus purge; and
- current macOS/Chrome limitation.

SECURITY must state that the extension exposes the user's authenticated browser,
that arbitrary page code is RCE-equivalent in the MCP process, how Keychain
pairing works, and how to report a vulnerability.

THIRD_PARTY_NOTICES must identify Playwright, its Apache-2.0 license, the fork
source, and the source commit from `runtime-lock.json`.

- [ ] **Step 4: Constrain npm package contents**

Add:

```json
{
  "files": [
    ".claude-plugin/",
    ".codex-plugin/",
    ".mcp.json",
    "adapters/",
    "agents/",
    "bin/",
    "builtins/",
    "lib/",
    "skills/",
    "templates/",
    "runtime-lock.json",
    "README.md",
    "SECURITY.md",
    "THIRD_PARTY_NOTICES.md"
  ]
}
```

Keep `private: true` until Plan 3's license and publisher gates are resolved.

- [ ] **Step 5: Run all Plan 2 verification**

Run:

```bash
npm test --prefix plugins/fast-browser
claude plugin validate plugins/fast-browser
npm pack --dry-run --prefix plugins/fast-browser
git diff --check
```

Expected: all commands pass and the dry-run includes both manifests, both MCP
descriptors, three skills, both agents/templates, and no test or personal file.

- [ ] **Step 6: Commit**

```bash
git add README.md .claude-plugin .agents/plugins plugins/fast-browser
git commit -m "docs(fast-browser): prepare dual-host plugin candidate"
```
