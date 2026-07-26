# Fast Browser Parity, Migration, and Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove full Claude Code/Codex parity against the packaged runtime, migrate Matt's existing setup transactionally, and produce a release-ready dual-host plugin candidate.

**Architecture:** A deterministic local browser fixture establishes direct MCP correctness and call-count budgets. Opt-in live-host harnesses then drive that same fixture through Claude Code and Codex against the user's Chrome extension. Migration remains additive until both hosts pass, rollback is exercised, and packaging/security gates produce a final readiness report.

**Tech Stack:** Node.js 20+ ESM, `node:test`, `@modelcontextprotocol/sdk` 1.29.0, local HTTP fixtures, Claude Code print mode, Codex exec JSONL, Fast Browser Chrome extension.

## Global Constraints

- Plans 1 and 2 must be accepted before this plan begins.
- Use the isolated mattstack and Playwright worktrees, not the user's dirty original worktrees.
- Browser use is authorized by the user's request and this documented E2E flow.
- Never target a real third-party site in automated tests.
- Do not use dangerous host permission-bypass flags.
- Do not delete the legacy Claude setup or `~/.playwright-mcp/`.
- Do not print the current extension token or copy it into a fixture.
- Direct-MCP fast flow budget is at most eight browser calls.
- A matching macro budget is exactly one browser call after setup/navigation.
- Wall-clock time is reported; a regression greater than 20 percent requires review rather than an automatic flaky failure.
- The live two-host test must prove no focus stealing and independent tab groups.
- Public publishing is forbidden until Matt selects a license and publisher credentials are explicitly authorized.

---

### Task 1: Add a deterministic direct-MCP parity fixture and metrics

**Files:**
- Create: `plugins/fast-browser/tests/fixtures/order-flow/index.html`
- Create: `plugins/fast-browser/tests/fixtures/order-flow/server.mjs`
- Create: `plugins/fast-browser/tests/e2e/helpers/mcp-client.mjs`
- Create: `plugins/fast-browser/tests/e2e/helpers/metrics.mjs`
- Create: `plugins/fast-browser/tests/e2e/direct-mcp.test.mjs`
- Modify: `plugins/fast-browser/package.json`

**Interfaces:**
- Consumes: the installed Plan 1 runtime CLI and MCP stdio.
- Produces:
  `startOrderFixture(): Promise<{ origin, close }>`;
  `startMcpClient(options): Promise<InstrumentedClient>`;
  `InstrumentedClient.callTool(name, args)`; and
  `InstrumentedClient.metrics(): { calls, byTool, elapsedMs }`.

- [ ] **Step 1: Create the deterministic five-step fixture**

The single page app must expose these accessible states:

1. `Start order` button;
2. `Customer name` textbox and `Continue`;
3. `Plan` combobox with `Starter`, `Team`, and `Scale`;
4. `Seats` spinbutton and `Review order`;
5. summary plus `Place order`;
6. final heading `Order complete` and an order ID derived deterministically
   from name, plan, and seats.

All state is in memory. The fixture makes no external request and accepts
`--port 0`, printing exactly one JSON line:

```json
{"origin":"http://127.0.0.1:54321"}
```

- [ ] **Step 2: Write the failing direct MCP tests**

Add exact development dependency:

```json
{
  "devDependencies": {
    "@modelcontextprotocol/sdk": "1.29.0"
  }
}
```

The fast-loop test calls:

```js
await browser.callTool('browser_navigate', { url: fixture.origin });
await browser.callTool('browser_snapshot', {});
const result = await browser.callTool('browser_run_code_unsafe', {
  code: `async page => {
    await page.getByRole('button', { name: 'Start order' }).click();
    await page.getByRole('textbox', { name: 'Customer name' }).fill('Ada');
    await page.getByRole('button', { name: 'Continue' }).click();
    await page.getByRole('combobox', { name: 'Plan' }).selectOption('team');
    await page.getByRole('spinbutton', { name: 'Seats' }).fill('7');
    await page.getByRole('button', { name: 'Review order' }).click();
    await page.getByRole('button', { name: 'Place order' }).click();
    await page.getByRole('heading', { name: 'Order complete' }).waitFor();
    return {
      heading: await page.getByRole('heading').innerText(),
      orderId: await page.getByTestId('order-id').innerText(),
    };
  }`,
});
assert.deepEqual(result, {
  heading: 'Order complete',
  orderId: 'ADA-TEAM-7',
});
assert.ok(browser.metrics().calls <= 8);
```

The macro test writes `order-flow.js` inside the test output directory and calls
only:

```js
await browser.callTool('browser_run_code_unsafe', {
  filename: 'order-flow.js',
  args: { customer: 'Grace', plan: 'scale', seats: 12 },
});
```

Assert the delta in call count is exactly one and result ID is
`GRACE-SCALE-12`.

- [ ] **Step 3: Run and verify the harness fails**

Run:

```bash
npm install --prefix plugins/fast-browser
npm run test:e2e --prefix plugins/fast-browser
```

Expected: FAIL because helpers and the `test:e2e` script are incomplete.

- [ ] **Step 4: Implement the instrumented client**

Use `Client` and `StdioClientTransport` from the SDK. Start the runtime artifact
directly with:

```js
[
  '--headless',
  '--browser', 'chrome',
  '--snapshot-mode=none',
  '--timeout-settle=200',
  `--output-dir=${outputDir}`,
]
```

Wrap every `client.callTool` to record monotonic start/end timestamps and tool
name. Parse only the MCP text result needed by the test; keep raw protocol
messages out of normal output.

Add:

```json
{
  "scripts": {
    "test:e2e": "node --test tests/e2e/direct-mcp.test.mjs"
  }
}
```

- [ ] **Step 5: Run direct parity and existing tests**

Run:

```bash
npm test --prefix plugins/fast-browser
npm run test:e2e --prefix plugins/fast-browser
```

Expected: all tests pass, fast flow uses no more than three calls in this
fixture, and macro delta is one.

- [ ] **Step 6: Commit**

```bash
git add plugins/fast-browser/package.json plugins/fast-browser/package-lock.json plugins/fast-browser/tests
git commit -m "test(fast-browser): add deterministic MCP parity flow"
```

### Task 2: Add real Claude Code and Codex host harnesses

**Files:**
- Create: `plugins/fast-browser/tests/e2e/helpers/host-runner.mjs`
- Create: `plugins/fast-browser/tests/e2e/host-parity.test.mjs`
- Create: `plugins/fast-browser/tests/e2e/host-result.schema.json`
- Create: `plugins/fast-browser/tests/e2e/prompts/claude.txt`
- Create: `plugins/fast-browser/tests/e2e/prompts/codex.txt`
- Modify: `plugins/fast-browser/package.json`

**Interfaces:**
- Consumes: installed local plugin, full profile, running fixture, and paired
  Chrome extension.
- Produces:
  `runClaudeHost(options): Promise<HostResult>`;
  `runCodexHost(options): Promise<HostResult>`; and this JSON result:

```js
{
  host: 'claude' | 'codex',
  ok: true,
  orderId: 'HOST-TEAM-5',
  browserCalls: 3,
  elapsedMs: 45000,
  tools: ['browser_navigate', 'browser_snapshot', 'browser_run_code_unsafe'],
}
```

- [ ] **Step 1: Write skipped-unless-authorized host tests**

```js
test('Claude Code completes the Fast Browser flow', {
  skip: process.env.FAST_BROWSER_LIVE_E2E !== '1',
}, async () => {
  const result = await runClaudeHost({ origin, pluginRoot, cwd });
  assert.equal(result.ok, true);
  assert.equal(result.orderId, 'CLAUDE-TEAM-5');
  assert.ok(result.browserCalls <= 8);
});

test('Codex completes the Fast Browser flow', {
  skip: process.env.FAST_BROWSER_LIVE_E2E !== '1',
}, async () => {
  const result = await runCodexHost({ origin, cwd });
  assert.equal(result.ok, true);
  assert.equal(result.orderId, 'CODEX-TEAM-5');
  assert.ok(result.browserCalls <= 8);
});
```

The prompts require Fast Browser, forbid other browser tools, name the supplied
local origin, and require output conforming to
`host-result.schema.json`.

- [ ] **Step 2: Run the default suite and verify clean skips**

Run:

```bash
npm run test:host --prefix plugins/fast-browser
```

Expected: both tests are reported as skipped, not failed.

- [ ] **Step 3: Implement Claude Code execution**

Spawn without a shell:

```js
[
  '-p',
  '--output-format', 'stream-json',
  '--verbose',
  '--model', 'sonnet',
  '--effort', 'medium',
  '--permission-mode', 'auto',
  '--no-chrome',
  '--no-session-persistence',
  '--plugin-dir', pluginRoot,
  prompt,
]
```

Parse assistant result and MCP tool events. Count only tools whose final segment
is `browser_*`. Reject use of `claude-in-chrome`. Apply a 5-minute process
timeout and a USD budget of `1.00` through `--max-budget-usd 1.00`.

- [ ] **Step 4: Implement Codex execution**

Spawn:

```js
[
  'exec',
  '--json',
  '--ephemeral',
  '--sandbox', 'read-only',
  '--cd', cwd,
  prompt,
]
```

Use the installed `fast-browser@mattstack` plugin and full-profile policy. Parse
JSONL events, count Fast Browser `browser_*` tools, and reject any browser-use
plugin or computer-use tool event. Apply the same 5-minute timeout.

- [ ] **Step 5: Add the host test script and parser tests**

Add:

```json
{
  "scripts": {
    "test:host": "node --test tests/e2e/host-parity.test.mjs"
  }
}
```

Unit-test both event parsers with checked-in synthetic JSONL containing one
successful flow, one wrong-browser-tool flow, malformed JSON, timeout, and a
host error.

- [ ] **Step 6: Run non-live tests and commit**

Run:

```bash
npm test --prefix plugins/fast-browser
npm run test:host --prefix plugins/fast-browser
```

Expected: parser tests pass and live tests skip.

```bash
git add plugins/fast-browser/package.json plugins/fast-browser/tests
git commit -m "test(fast-browser): add Claude and Codex host harnesses"
```

### Task 3: Install the local candidate and pass live two-host E2E

**Files:**
- Modify: `plugins/fast-browser/runtime-lock.json`
- Create: `.local-dev/fast-browser/live-e2e-results.json`
- Mutate through the CLI after approval: `~/.fast-browser/`,
  Claude user plugin state, Codex user plugin state, Fast Browser-owned routing,
  Codex browser-driver agent, and macOS Keychain.

**Interfaces:**
- Consumes: Plan 1 local release JSON and Plan 2 setup/doctor commands.
- Produces: a paired local full-profile installation and redacted live E2E
  results for both hosts.

- [ ] **Step 1: Pin the release candidate without a personal path**

Copy the Plan 1 release fields into `runtime-lock.json`. Add these intended
immutable publication URLs while keeping commit, version, extension ID, and
SHA-256 unchanged:

```text
https://github.com/m4ttheweric/playwright/releases/download/fast-browser-v0.1.0-alpha.1/fast-browser-mcp-0.1.0-alpha.1.tar.gz
https://github.com/m4ttheweric/playwright/releases/download/fast-browser-v0.1.0-alpha.1/fast-browser-extension-0.1.0-alpha.1.zip
```

Do not add a local `file://` URL to the committed lock.

Run:

```bash
npm test --prefix plugins/fast-browser
```

Expected: runtime lock and checksum tests pass.

- [ ] **Step 2: Run additive local setup**

Run from the mattstack worktree:

```bash
node plugins/fast-browser/bin/fast-browser.mjs setup --host both --profile full --source "$PWD" --runtime-lock /Users/matt/Documents/GitHub/playwright/.worktrees/fast-browser-runtime/fast-browser-dist/fast-browser-release-0.1.0-alpha.1.json
```

Expected: the runtime and extension artifact install, both plugins register, and
doctor reports only extension installation/pairing checks as pending. The legacy
Claude MCP entry and `.playwright-mcp` data remain present.

- [ ] **Step 3: Complete the required Chrome user action**

The CLI prints the exact unpacked extension directory. Ask Matt to:

1. open `chrome://extensions`;
2. enable Developer mode;
3. load that exact directory;
4. open Fast Browser's status page; and
5. copy its raw reconnect token.

Then run:

```bash
node plugins/fast-browser/bin/fast-browser.mjs configure --profile full --connection auto --record-sessions --retention-days 30
```

Paste the token only into `/usr/bin/security`'s hidden prompt. Do not paste it
into the conversation or a command argument.

- [ ] **Step 4: Pass doctor before model-driven E2E**

Run:

```bash
node plugins/fast-browser/bin/fast-browser.mjs doctor --json
```

Expected: all checks through `tool-contract` pass, and JSON contains only
pairing presence, never the token.

- [ ] **Step 5: Run live Claude and Codex tests sequentially**

Run:

```bash
FAST_BROWSER_LIVE_E2E=1 npm run test:host --prefix plugins/fast-browser
```

Expected: both flows pass, each uses at most eight browser calls, neither uses
another browser plugin, and results include distinct order IDs.

- [ ] **Step 6: Run the simultaneous-client focus test**

Start both host harness processes against two distinct fixture flows, keep a
user-owned Chrome tab focused, and assert through the extension status page and
test harness that:

- both clients stay connected;
- tab groups have distinct Claude/Codex workspace labels;
- the user-owned tab remains focused;
- terminating Claude leaves Codex functional; and
- reconnecting Claude leaves Codex functional.

Write only redacted metrics and group labels to
`.local-dev/fast-browser/live-e2e-results.json`.

- [ ] **Step 7: Commit the lock and redacted evidence**

```bash
git add plugins/fast-browser/runtime-lock.json .local-dev/fast-browser/live-e2e-results.json
git commit -m "test(fast-browser): verify live dual-host parity"
```

### Task 4: Dry-run, apply, roll back, and reapply Matt's migration

**Files:**
- Create through CLI: `~/.fast-browser/backups/<timestamp>/`
- Create: `.local-dev/fast-browser/migration-verification.json`
- Modify only through the migration adapter: recognized legacy Claude
  configuration after successful verification.

**Interfaces:**
- Consumes: the paired, passing candidate from Task 3.
- Produces: verified migration manifest, exercised rollback, and final
  full-profile configuration for both hosts.

- [ ] **Step 1: Run a redacted dry-run**

Run:

```bash
node plugins/fast-browser/bin/fast-browser.mjs migrate --host both --profile full --dry-run --json
```

Expected: report lists only recognized Playwright MCP/rule/agent/skill/data
targets, says source data will be copied rather than moved, and contains no
token value.

- [ ] **Step 2: Compare dry-run targets with the approved inventory**

Verify:

- unrelated Claude MCP servers are absent;
- unrelated Claude rules and agents are absent;
- unrelated Codex config is absent;
- `~/.playwright-mcp` is never a deletion target;
- personal macros are import-only;
- the existing order-wizard benchmark is not added to Git; and
- rollback target paths are exact.

If any broad or unexplained target appears, stop and fix migration matching
before applying.

- [ ] **Step 3: Apply migration with verification callback**

Run:

```bash
node plugins/fast-browser/bin/fast-browser.mjs migrate --host both --profile full
```

Expected: backup and data import complete, both host checks pass, recognized
legacy registrations are removed, legacy data remains, and a rollback command
is printed.

- [ ] **Step 4: Re-run doctor and host parity**

Run:

```bash
node plugins/fast-browser/bin/fast-browser.mjs doctor --json
FAST_BROWSER_LIVE_E2E=1 npm run test:host --prefix plugins/fast-browser
```

Expected: all checks and both host flows pass after legacy registration removal.

- [ ] **Step 5: Exercise rollback**

Run the exact rollback command emitted by migration. Verify byte hashes for
restored recognized files match the backup manifest, the legacy Claude path is
active again, and `~/.fast-browser` data remains.

Run the legacy Claude smoke test once. It must pass.

- [ ] **Step 6: Reapply migration and final verification**

Run:

```bash
node plugins/fast-browser/bin/fast-browser.mjs migrate --host both --profile full
node plugins/fast-browser/bin/fast-browser.mjs doctor --json
FAST_BROWSER_LIVE_E2E=1 npm run test:host --prefix plugins/fast-browser
```

Expected: reapplication is idempotent and both hosts pass.

- [ ] **Step 7: Record redacted migration evidence and commit**

Write:

```js
{
  schemaVersion: 1,
  migratedAt,
  backupManifest,
  rollbackExercised: true,
  reapplied: true,
  legacyDataPreserved: true,
  doctorOk: true,
  claudeOk: true,
  codexOk: true,
}
```

The file may contain paths and hashes but no secret or recorded page content.

```bash
git add .local-dev/fast-browser/migration-verification.json
git commit -m "test(fast-browser): verify reversible local migration"
```

### Task 5: Complete release gates and readiness report

**Files:**
- Modify after user choice: `plugins/fast-browser/package.json`
- Modify after user choice: `plugins/fast-browser/.claude-plugin/plugin.json`
- Modify after user choice: `plugins/fast-browser/.codex-plugin/plugin.json`
- Modify after user choice: `plugins/fast-browser/README.md`
- Modify after user choice: repository license files
- Create: `plugins/fast-browser/tests/integration/release-gates.test.mjs`
- Create: `.local-dev/fast-browser/release-readiness.md`

**Interfaces:**
- Consumes: all accepted commits, test evidence, artifact lock, and Matt's
  explicit license decision.
- Produces: a packable public candidate and an exact list of any
  credential-gated publication actions.

- [ ] **Step 1: Add failing release gates**

The test must fail while either condition is true:

```js
assert.notEqual(packageJson.license, 'UNLICENSED');
assert.equal(packageJson.private, false);
```

It must also assert:

- both plugin manifests use the same SPDX license and version;
- the selected license file exists;
- Playwright notices exist;
- runtime lock URLs are immutable and checksummed;
- marketplace versions equal plugin version;
- `npm pack --dry-run` contains no test, session, token, personal macro, or
  maintainer absolute path; and
- both host validators succeed.

- [ ] **Step 2: Run and verify the intentional license failure**

Run:

```bash
npm test --prefix plugins/fast-browser
```

Expected: only the license/private publication gate fails.

- [ ] **Step 3: Obtain and apply Matt's license decision**

Ask Matt to choose the plugin/repository license before public publication.
Apply the chosen SPDX identifier consistently, add its exact license text,
change `private` to `false`, and document that forked Playwright artifacts
remain Apache-2.0.

Do not infer a license or publish while this decision is absent.

- [ ] **Step 4: Run the complete local release suite**

Run:

```bash
npm test --prefix plugins/fast-browser
npm run test:e2e --prefix plugins/fast-browser
FAST_BROWSER_LIVE_E2E=1 npm run test:host --prefix plugins/fast-browser
claude plugin validate plugins/fast-browser
npm pack --dry-run --prefix plugins/fast-browser
git diff --check
```

In the Playwright worktree, run:

```bash
npm run build
npm run test-mcp -- fast-browser-contract.spec.ts fast-browser-artifacts.spec.ts run-code.spec.ts snapshot-mode.spec.ts timeouts.spec.ts
npm run test-extension -- extension.spec.ts multi-connection.spec.ts tab-grouping.spec.ts tab-management.spec.ts
```

Expected: every command passes.

- [ ] **Step 5: Write the release-readiness report**

Include:

- mattstack and Playwright commit IDs;
- plugin, runtime, extension, and protocol versions;
- artifact filenames and SHA-256 values;
- extension ID;
- unit/integration/E2E counts;
- Claude/Codex call counts and elapsed times;
- migration and rollback result;
- secret/path/package scans;
- selected license;
- exact unpublished actions such as npm scope creation, GitHub push/release,
  and Chrome Web Store submission; and
- explicit statement that no external publication was performed without user
  authorization.

- [ ] **Step 6: Commit**

```bash
git add plugins/fast-browser .claude-plugin .agents/plugins .local-dev/fast-browser/release-readiness.md
git commit -m "chore(fast-browser): complete release readiness gates"
```

- [ ] **Step 7: Run verification-before-completion**

Use `superpowers:verification-before-completion`. Re-run the commands it
requires from fresh shells, inspect both worktree statuses, and report only
evidence from the final runs.
