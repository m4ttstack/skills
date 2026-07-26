# Fast Browser Runtime and Extension Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the existing Playwright fork changes into versioned, test-covered Fast Browser MCP runtime and Chrome extension artifacts.

**Architecture:** Keep browser-engine behavior in `m4ttheweric/playwright`. Add a configurable extension identity so the fork remains testable without owning Microsoft's extension ID, brand the fork-built extension as Fast Browser, and package the built `playwright-core` plus a small MCP launcher into a checksum-addressed tarball.

**Tech Stack:** Playwright monorepo TypeScript, Playwright Test, Node.js 20+, Chrome Manifest V3, npm workspaces, GitHub Actions.

## Global Constraints

- Work in an isolated Playwright worktree created from the current `multi-connection-extension` HEAD.
- Preserve all existing upstream license headers.
- Do not change the default upstream extension ID unless `--extension-id` is supplied.
- The Fast Browser extension must use an identity distinct from Microsoft's `mmlmfjhmonkocbjadbfplnigmagldckm`.
- The packaged runtime must run with Node.js 20+ and must not install dependencies at startup.
- The artifact build must use fixed contents for a given source commit and declared product version; every produced byte stream is addressed by its recorded SHA-256.
- Release metadata must include artifact filenames, SHA-256 values, source commit, extension ID, extension version, and protocol version.
- `browser_run_code_unsafe` must remain an action with `readOnlyHint: false` and `destructiveHint: true`.

---

### Task 1: Parameterize and brand the extension identity

**Files:**
- Modify: `packages/playwright-core/src/tools/mcp/config.d.ts`
- Modify: `packages/playwright-core/src/tools/mcp/config.ts`
- Modify: `packages/playwright-core/src/tools/mcp/program.ts`
- Modify: `packages/playwright-core/src/tools/mcp/browserFactory.ts`
- Modify: `packages/playwright-core/src/tools/mcp/extensionContextFactory.ts`
- Modify: `packages/playwright-core/src/tools/utils/extension.ts`
- Modify: `packages/extension/manifest.json`
- Modify: `packages/extension/src/ui/connect.tsx`
- Modify: `packages/extension/src/ui/status.tsx`
- Modify: `packages/extension/src/ui/status.html`
- Modify: `packages/extension/README.md`
- Modify: `tests/extension/extension-fixtures.ts`
- Modify: `tests/extension/extension.spec.ts`
- Modify: `tests/mcp/config.spec.ts`

**Interfaces:**
- Consumes: existing `CLIOptions`, `Config`, `FullConfig`, and extension relay behavior.
- Produces: CLI option `--extension-id <id>`; env key
  `PLAYWRIGHT_MCP_EXTENSION_ID`; config property `extensionId?: string`;
  `isPlaywrightExtensionInstalled(userDataDir, extensionId)`; and
  `createExtensionBrowser(..., extensionId, extensionInstallUrl)`.

- [ ] **Step 1: Write failing tests for a non-default extension ID**

In `tests/extension/extension.spec.ts`, add a profile-detection test that creates
an extension directory for a synthetic ID and calls the built detection helper:

```ts
test('accepts a configured extension id', async ({}, testInfo) => {
  const { isPlaywrightExtensionInstalled } =
    require('../../packages/playwright-core/lib/tools/utils/extension');
  const userDataDir = testInfo.outputPath('profile');
  const extensionId = 'abcdefghijklmnopabcdefghijklmnop';
  await fs.promises.mkdir(path.join(userDataDir, 'Default', 'Extensions', extensionId), { recursive: true });

  expect(await isPlaywrightExtensionInstalled(userDataDir, extensionId)).toBe(true);
  expect(await isPlaywrightExtensionInstalled(
    userDataDir,
    'ponmlkjihgfedcbaponmlkjihgfedcba',
  )).toBe(false);
});
```

In the manifest test setup, derive the test ID from the manifest key instead of
hardcoding Microsoft's ID:

```ts
import crypto from 'crypto';
import fsSync from 'fs';

function extensionIdFromManifestKey(key: string): string {
  const alphabet = 'abcdefghijklmnop';
  const digest = crypto.createHash('sha256').update(Buffer.from(key, 'base64')).digest().subarray(0, 16);
  return [...digest].map(byte => alphabet[byte >> 4] + alphabet[byte & 15]).join('');
}

const extensionManifest = JSON.parse(fsSync.readFileSync(
  path.resolve(__dirname, '../../packages/extension/manifest.json'),
  'utf8',
));
export const extensionId = extensionIdFromManifestKey(extensionManifest.key);
```

Add:

```ts
test('Fast Browser extension does not reuse the Microsoft extension id', () => {
  expect(extensionId).not.toBe('mmlmfjhmonkocbjadbfplnigmagldckm');
});
```

Add a config test that starts with
`--extension-id=abcdefghijklmnopabcdefghijklmnop`, calls
`browser_get_config`, and expects the serialized config to contain that exact
`extensionId`. Add a second case with
`PLAYWRIGHT_MCP_EXTENSION_ID=ponmlkjihgfedcbaponmlkjihgfedcba`.

- [ ] **Step 2: Run the focused tests and verify the new behavior fails**

Run:

```bash
npm run build
npm run test-extension -- extension.spec.ts
```

Expected: config tests fail because `--extension-id` and its env form are
unknown, and the identity test fails because the manifest still contains
Microsoft's key.

- [ ] **Step 3: Add the configurable identity**

Add to `CLIOptions` and `Config`:

```ts
extensionId?: string;
```

Register the CLI and environment forms:

```ts
.option('--extension-id <id>', 'Chrome extension id used by --extension')
```

```ts
options.extensionId = envToString(e.PLAYWRIGHT_MCP_EXTENSION_ID);
```

Propagate the value into resolved config and call:

```ts
browser = await createExtensionBrowser(
  channel,
  executablePath,
  clientInfo.clientName,
  clientInfo.cwd,
  config.extensionId ?? playwrightExtensionId,
  config.extensionId ? undefined : playwrightExtensionInstallUrl,
);
```

Change extension detection to accept the ID explicitly:

```ts
export async function isPlaywrightExtensionInstalled(
  userDataDir: string,
  extensionId: string = playwrightExtensionId,
): Promise<boolean> {
  // Existing profile traversal, passing extensionId into the profile helper.
}
```

When no store URL is known, use an actionable neutral error:

```ts
const installHint = extensionInstallUrl
  ? ` Install it from ${extensionInstallUrl}`
  : ' Install the matching extension and run the command again.';
throw new Error(`Browser extension "${extensionId}" not found in "${userDataDir}".${installHint}`);
```

- [ ] **Step 4: Generate and commit a Fast Browser public extension key**

Generate a one-time RSA keypair outside the repository:

```bash
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out /tmp/fast-browser-extension-private.pem
openssl pkey -in /tmp/fast-browser-extension-private.pem -pubout -outform DER -out /tmp/fast-browser-extension-public.der
openssl base64 -A -in /tmp/fast-browser-extension-public.der
```

Replace `manifest.json`'s `key` with the final command's output. Do not commit or
copy the private key. Delete the temporary private and DER files after the
manifest-derived extension ID has been recorded in the test output.

Set these manifest values:

```json
{
  "name": "Fast Browser",
  "description": "Connect your existing Chrome session to Fast Browser for local Claude Code and Codex automation.",
  "action": {
    "default_title": "Fast Browser"
  }
}
```

Update visible UI strings and README links to say `Fast Browser`. Until a store
URL exists, the version-mismatch link must point to
`https://github.com/m4ttheweric/mattstack/tree/main/plugins/fast-browser`.

- [ ] **Step 5: Rebuild and run the focused tests**

Run:

```bash
npm run build
npm run test-extension -- extension.spec.ts tab-grouping.spec.ts
npm run test-mcp -- config.spec.ts config-resolve.spec.ts
```

Expected: all selected tests pass, the printed extension ID is not Microsoft's
ID, and the default no-argument path still recognizes the upstream ID.

- [ ] **Step 6: Commit**

```bash
git add packages/playwright-core/src/tools/mcp packages/playwright-core/src/tools/utils/extension.ts packages/extension tests/extension tests/mcp/config.spec.ts
git commit -m "feat(extension): support Fast Browser identity"
```

### Task 2: Lock pairing, concurrency, focus, snapshot, settle, and macro behavior

**Files:**
- Modify: `packages/extension/src/ui/authToken.tsx`
- Modify: `packages/extension/src/ui/connect.tsx`
- Modify: `tests/extension/extension.spec.ts`
- Modify: `tests/extension/multi-connection.spec.ts`
- Modify: `tests/mcp/snapshot-mode.spec.ts`
- Modify: `tests/mcp/timeouts.spec.ts`
- Modify: `tests/mcp/run-code.spec.ts`
- Create: `tests/mcp/fast-browser-contract.spec.ts`

**Interfaces:**
- Consumes: the extension ID from Task 1 and existing fork behavior.
- Produces: a raw-token copy UI suitable for a hidden CLI prompt and one
  regression suite named `fast-browser-contract.spec.ts`.

- [ ] **Step 1: Write failing pairing and reconnection tests**

Change the token test to require a raw token:

```ts
const token = await page.locator('.auth-token-code').textContent();
expect(token).toMatch(/^[A-Za-z0-9_-]{40,}$/);
expect(token).not.toContain('PLAYWRIGHT_MCP_EXTENSION_TOKEN=');
```

Add to `tests/extension/multi-connection.spec.ts`:

```ts
test('token-bypass clients do not steal focus and can reconnect independently', async ({
  browserWithExtension,
  startClient,
  server,
}) => {
  const browserContext = await browserWithExtension.launch();
  const keeper = await browserContext.newPage();
  await keeper.goto(server.PREFIX + '/keeper');
  await keeper.bringToFront();

  const statusPage = await browserContext.newPage();
  await statusPage.goto(`chrome-extension://${extensionId}/status.html`);
  const token = await statusPage.locator('.auth-token-code').textContent();
  await statusPage.close();

  const connect = async (name: string) => {
    const { client } = await startClient({
      args: ['--extension', `--extension-id=${extensionId}`],
      clientName: name,
      roots: [{ name: 'workspace', uri: `file:///tmp/${name}` }],
      env: {
        PWTEST_EXTENSION_USER_DATA_DIR: browserWithExtension.userDataDir,
        PLAYWRIGHT_MCP_EXTENSION_TOKEN: token!,
      },
    });
    await client.callTool({ name: 'browser_navigate', arguments: { url: server.PREFIX + '/' + name } });
    return client;
  };

  const clientA = await connect('claude');
  const clientB = await connect('codex');
  expect(await keeper.evaluate(() => document.hasFocus())).toBe(true);
  await clientA.close();
  await connect('claude-reconnected');
  expect((await clientB.callTool({
    name: 'browser_navigate',
    arguments: { url: server.PREFIX + '/codex-still-alive' },
  })).isError ?? false).toBe(false);
});
```

- [ ] **Step 2: Write the consolidated MCP contract test**

In `fast-browser-contract.spec.ts`, assert tool metadata and explicit snapshot
behavior:

```ts
import { test, expect } from './fixtures';

test('unsafe run code is destructive and snapshot-none remains explicit', async ({
  startClient,
  server,
}) => {
  server.setContent('/', '<button>Ready</button>', 'text/html');
  const { client } = await startClient({
    args: ['--snapshot-mode=none', '--timeout-settle=200'],
  });
  const tools = await client.listTools();
  const unsafe = tools.tools.find(tool => tool.name === 'browser_run_code_unsafe');
  expect(unsafe?.annotations).toMatchObject({
    readOnlyHint: false,
    destructiveHint: true,
  });

  const navigate = await client.callTool({
    name: 'browser_navigate',
    arguments: { url: server.PREFIX },
  });
  expect(navigate).not.toHaveResponse({ snapshot: expect.anything() });

  expect(await client.callTool({ name: 'browser_snapshot' })).toHaveResponse({
    inlineSnapshot: expect.stringContaining('button "Ready"'),
  });
});
```

Retain the existing filename-plus-args tests and add an assertion that the
returned code includes the serialized arguments but not a page dump.

- [ ] **Step 3: Verify the raw-token expectation fails**

Run:

```bash
npm run build
npm run test-extension -- extension.spec.ts multi-connection.spec.ts
npm run test-mcp -- fast-browser-contract.spec.ts run-code.spec.ts snapshot-mode.spec.ts timeouts.spec.ts
```

Expected: the raw-token assertion fails while the already-implemented fork
contracts pass or expose any missing regression.

- [ ] **Step 4: Change the extension token UI**

In `authToken.tsx`, render and copy only the raw token:

```tsx
<div className='auth-token-description'>
  Paste this token into the hidden Fast Browser setup prompt to enable automatic reconnect:
</div>
<div className='auth-token-container'>
  <code className='auth-token-code'>{authToken}</code>
  <button
    className='auth-token-refresh'
    title='Generate new token'
    aria-label='Generate new token'
    onClick={onRegenerateToken}
  >
    {icons.refresh()}
  </button>
  <CopyToClipboard value={authToken} />
</div>
```

Remove `authTokenCode()`. Keep token generation and local storage unchanged.

- [ ] **Step 5: Run the full focused contract suites**

Run:

```bash
npm run build
npm run test-extension -- extension.spec.ts multi-connection.spec.ts tab-grouping.spec.ts
npm run test-mcp -- fast-browser-contract.spec.ts run-code.spec.ts snapshot-mode.spec.ts timeouts.spec.ts
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add packages/extension/src/ui tests/extension tests/mcp
git commit -m "test(fast-browser): lock runtime and extension contract"
```

### Task 3: Build self-contained runtime and extension artifacts

**Files:**
- Create: `packages/fast-browser-mcp/package.json`
- Create: `packages/fast-browser-mcp/cli.cjs`
- Create: `packages/fast-browser-mcp/README.md`
- Create: `packages/fast-browser-mcp/LICENSE`
- Create: `packages/fast-browser-mcp/NOTICE`
- Create: `utils/fast_browser/build_artifacts.mjs`
- Create: `tests/mcp/fast-browser-artifacts.spec.ts`
- Modify: `package.json`

**Interfaces:**
- Consumes: built `packages/playwright-core`, built `packages/extension/dist`,
  and the manifest-derived Fast Browser extension ID.
- Produces:
  `node utils/fast_browser/build_artifacts.mjs --version <semver> --out-dir <dir>`;
  `fast-browser-mcp-<version>.tar.gz`;
  `fast-browser-extension-<version>.zip`; and
  `fast-browser-release-<version>.json`.

- [ ] **Step 1: Write a failing artifact test**

Create `tests/mcp/fast-browser-artifacts.spec.ts`:

```ts
import crypto from 'crypto';
import fs from 'fs';
import os from 'os';
import path from 'path';
import { execFileSync, spawnSync } from 'child_process';
import { test, expect } from './fixtures';

test('builds self-contained Fast Browser artifacts', async () => {
  const outDir = fs.mkdtempSync(path.join(os.tmpdir(), 'fast-browser-artifacts-'));
  execFileSync(process.execPath, [
    'utils/fast_browser/build_artifacts.mjs',
    '--version', '0.1.0-test.1',
    '--out-dir', outDir,
  ], { cwd: path.resolve(__dirname, '../..'), stdio: 'inherit' });

  const release = JSON.parse(fs.readFileSync(
    path.join(outDir, 'fast-browser-release-0.1.0-test.1.json'),
    'utf8',
  ));
  expect(release).toMatchObject({
    schemaVersion: 1,
    productVersion: '0.1.0-test.1',
    protocolVersion: 2,
    runtime: { node: '>=20' },
  });
  for (const artifact of [release.runtime, release.extension]) {
    const bytes = fs.readFileSync(path.join(outDir, artifact.file));
    expect(crypto.createHash('sha256').update(bytes).digest('hex')).toBe(artifact.sha256);
  }

  execFileSync('tar', ['-xzf', path.join(outDir, release.runtime.file), '-C', outDir]);
  const help = spawnSync(process.execPath, [
    path.join(outDir, 'fast-browser-mcp', 'cli.cjs'),
    '--help',
  ], { encoding: 'utf8' });
  expect(help.status).toBe(0);
  expect(help.stdout).toContain('Playwright MCP');
});
```

- [ ] **Step 2: Run the test and verify the builder is missing**

Run:

```bash
npm run build
npm run test-mcp -- fast-browser-artifacts.spec.ts
```

Expected: FAIL because `utils/fast_browser/build_artifacts.mjs` does not exist.

- [ ] **Step 3: Add the packaged launcher**

Create `packages/fast-browser-mcp/package.json`:

```json
{
  "name": "@mattstack/fast-browser-mcp",
  "version": "0.1.0",
  "private": true,
  "description": "Self-contained Playwright MCP runtime for Fast Browser",
  "license": "Apache-2.0",
  "engines": {
    "node": ">=20"
  },
  "bin": {
    "fast-browser-mcp": "cli.cjs"
  }
}
```

Create `cli.cjs`:

```js
#!/usr/bin/env node
'use strict';

const path = require('path');
const packageJson = require('./package.json');
const { program } = require(path.join(__dirname, 'playwright-core/lib/utilsBundle'));
const { tools } = require(path.join(__dirname, 'playwright-core/lib/coreBundle'));

const p = program
    .version(packageJson.version)
    .name('Fast Browser MCP');
tools.decorateMCPCommand(p, packageJson.version);
void program.parseAsync(process.argv);
```

Copy the upstream `LICENSE` and `NOTICE` into this package and state in the
README that the artifact bundles the forked `playwright-core`.

- [ ] **Step 4: Implement the artifact builder**

The builder must:

1. parse `--version` and `--out-dir`;
2. reject versions that do not match
   `/^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$/`;
3. create a temporary staging directory with `fs.mkdtemp`;
4. copy the launcher package and built `packages/playwright-core` npm payload
   into `fast-browser-mcp/playwright-core`;
5. overwrite the staged launcher package version with `--version`;
6. create the runtime tarball and extension zip with `tar` and `zip`;
7. compute SHA-256 for both;
8. read the extension ID from the manifest key; and
9. write this exact release shape:

```js
{
  schemaVersion: 1,
  productVersion,
  sourceCommit,
  protocolVersion: 2,
  runtime: {
    file: `fast-browser-mcp-${productVersion}.tar.gz`,
    sha256: runtimeSha256,
    node: '>=20',
  },
  extension: {
    file: `fast-browser-extension-${productVersion}.zip`,
    sha256: extensionSha256,
    id: extensionId,
    version: extensionManifest.version,
  },
}
```

Use `spawnSync(command, args, { shell: false })` for `npm pack`, `tar`, and
`zip`; reject nonzero exit codes with the command and captured stderr. Always
remove the temporary staging directory in `finally`.

Add:

```json
{
  "scripts": {
    "build-fast-browser": "node utils/fast_browser/build_artifacts.mjs"
  }
}
```

to the root scripts without changing existing scripts.

- [ ] **Step 5: Run artifact and MCP contract tests**

Run:

```bash
npm run build
npm run test-mcp -- fast-browser-artifacts.spec.ts fast-browser-contract.spec.ts run-code.spec.ts
```

Expected: PASS. Inspect the test output directory and confirm the extracted
runtime contains no `src/`, `.git/`, or absolute checkout path.

- [ ] **Step 6: Commit**

```bash
git add packages/fast-browser-mcp utils/fast_browser tests/mcp/fast-browser-artifacts.spec.ts package.json
git commit -m "build(fast-browser): package runtime and extension"
```

### Task 4: Add CI and release automation for Fast Browser artifacts

**Files:**
- Create: `.github/workflows/tests_fast_browser.yml`
- Create: `.github/workflows/publish_fast_browser.yml`
- Modify: `packages/fast-browser-mcp/README.md`
- Modify: `packages/extension/README.md`

**Interfaces:**
- Consumes: `npm run build-fast-browser` from Task 3.
- Produces: CI artifact `fast-browser-artifacts`; release tag convention
  `fast-browser-v<semver>`; and GitHub release assets matching the release JSON.

- [ ] **Step 1: Add a workflow-shape test**

Extend `fast-browser-artifacts.spec.ts`:

```ts
test('release workflows call the checked-in artifact builder', () => {
  const testWorkflow = fs.readFileSync('.github/workflows/tests_fast_browser.yml', 'utf8');
  const publishWorkflow = fs.readFileSync('.github/workflows/publish_fast_browser.yml', 'utf8');
  expect(testWorkflow).toContain('npm run test-mcp -- fast-browser-');
  expect(testWorkflow).toContain('npm run test-extension -- extension.spec.ts multi-connection.spec.ts tab-grouping.spec.ts');
  expect(publishWorkflow).toContain('node utils/fast_browser/build_artifacts.mjs');
  expect(publishWorkflow).toContain('gh release upload');
});
```

- [ ] **Step 2: Run the test and verify the workflows are missing**

Run:

```bash
npm run test-mcp -- fast-browser-artifacts.spec.ts
```

Expected: FAIL with `ENOENT` for `tests_fast_browser.yml`.

- [ ] **Step 3: Create the Fast Browser CI workflow**

`tests_fast_browser.yml` must run on pull requests that touch the extension,
MCP tools, Fast Browser package, Fast Browser tests, builder, or either workflow.
Use `macos-latest`, Node 22, `npm ci`,
`npx playwright install chromium`, and:

```yaml
- run: npm run build
- run: npm run test-mcp -- fast-browser-contract.spec.ts fast-browser-artifacts.spec.ts run-code.spec.ts snapshot-mode.spec.ts timeouts.spec.ts
- run: npm run test-extension -- extension.spec.ts multi-connection.spec.ts tab-grouping.spec.ts
```

Upload the locally built artifact directory after:

```yaml
- run: node utils/fast_browser/build_artifacts.mjs --version 0.1.0-ci.${{ github.run_number }} --out-dir fast-browser-dist
```

- [ ] **Step 4: Create the release workflow**

Trigger only on a published GitHub release whose tag starts with
`fast-browser-v`. Grant `contents: write`, build once, and upload every file:

```yaml
- name: Derive version
  id: version
  run: echo "value=${GITHUB_REF_NAME#fast-browser-v}" >> "$GITHUB_OUTPUT"
- run: node utils/fast_browser/build_artifacts.mjs --version "${{ steps.version.outputs.value }}" --out-dir fast-browser-dist
- env:
    GH_TOKEN: ${{ github.token }}
  run: gh release upload "$GITHUB_REF_NAME" fast-browser-dist/* --clobber
```

Do not add npm or Chrome Web Store secrets to this workflow. Those publication
steps remain separate external-account gates.

- [ ] **Step 5: Document local and release builds**

In both READMEs, document:

```bash
npm ci
npm run build
node utils/fast_browser/build_artifacts.mjs --version 0.1.0-alpha.1 --out-dir fast-browser-dist
```

Explain that the release JSON is the only file `mattstack/runtime-lock.json`
should consume and that the extension zip is installed unpacked until a Fast
Browser store listing exists.

- [ ] **Step 6: Run tests and a local artifact build**

Run:

```bash
npm run build
npm run test-mcp -- fast-browser-contract.spec.ts fast-browser-artifacts.spec.ts run-code.spec.ts snapshot-mode.spec.ts timeouts.spec.ts
npm run test-extension -- extension.spec.ts multi-connection.spec.ts tab-grouping.spec.ts
node utils/fast_browser/build_artifacts.mjs --version 0.1.0-alpha.1 --out-dir fast-browser-dist
```

Expected: all tests pass and the output contains exactly one runtime tarball,
one extension zip, and one release JSON.

- [ ] **Step 7: Commit**

```bash
git add .github/workflows/tests_fast_browser.yml .github/workflows/publish_fast_browser.yml packages/fast-browser-mcp/README.md packages/extension/README.md
git commit -m "ci(fast-browser): build versioned release artifacts"
```

### Task 5: Verify and hand off the runtime contract

**Files:**
- Create: `packages/fast-browser-mcp/COMPATIBILITY.md`
- Modify: `.gitignore`
- Modify only if a test exposes a defect: files owned by Tasks 1-4.

**Interfaces:**
- Consumes: every runtime and extension interface in this plan.
- Produces: a clean final source commit plus an ignored local
  `fast-browser-dist/fast-browser-release-0.1.0-alpha.1.json` for the mattstack
  worktree.

- [ ] **Step 1: Document and ignore the local handoff directory**

`COMPATIBILITY.md` must state:

```text
Fast Browser product 0.1.x consumes release schema 1 and extension protocol 2.
The release JSON is authoritative for filenames, checksums, extension ID,
extension version, Node floor, and source commit.
Runtime startup must reject any other schema or protocol version.
```

Add `/fast-browser-dist/` to the repository root `.gitignore`.

- [ ] **Step 2: Commit the final source contract**

```bash
git add .gitignore packages/fast-browser-mcp/COMPATIBILITY.md
git commit -m "docs(fast-browser): define runtime compatibility contract"
```

- [ ] **Step 3: Run the complete focused suites from a clean build**

Run:

```bash
npm run build
npm run test-mcp -- fast-browser-contract.spec.ts fast-browser-artifacts.spec.ts run-code.spec.ts snapshot-mode.spec.ts timeouts.spec.ts
npm run test-extension -- extension.spec.ts multi-connection.spec.ts tab-grouping.spec.ts tab-management.spec.ts
```

Expected: all tests pass.

- [ ] **Step 4: Build the candidate artifacts**

Run:

```bash
node utils/fast_browser/build_artifacts.mjs --version 0.1.0-alpha.1 --out-dir fast-browser-dist
```

Expected: the release JSON names the current source commit and contains valid
SHA-256 values for both files.

- [ ] **Step 5: Smoke-test the extracted runtime**

Run:

```bash
fast_browser_smoke_dir="$(mktemp -d)"
tar -xzf fast-browser-dist/fast-browser-mcp-0.1.0-alpha.1.tar.gz -C "$fast_browser_smoke_dir"
node "$fast_browser_smoke_dir/fast-browser-mcp/cli.cjs" --help
```

Expected: exit 0 and help includes `--extension-id`, `--snapshot-mode`,
`--timeout-settle`, and `--save-session`.

- [ ] **Step 6: Hand off the candidate manifest**

Keep the generated release JSON at:

```text
fast-browser-dist/fast-browser-release-0.1.0-alpha.1.json
```

Pass that exact absolute path to the mattstack Plan 2 runtime-lock task. Do not
commit the tarball, extension zip, release JSON, extracted runtime, or private
extension-key material.

- [ ] **Step 7: Verify repository hygiene**

Run:

```bash
git diff --check
git status --short
git grep -n '/Users/matt\\|PLAYWRIGHT_MCP_EXTENSION_TOKEN=' -- packages/fast-browser-mcp packages/extension utils/fast_browser .github/workflows
```

Expected: `git diff --check` succeeds; `git status --short` is empty because
`fast-browser-dist/` is ignored; the grep finds no personal absolute path and no
real token.
