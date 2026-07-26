# Fast Browser Transactional Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the two load-bearing final-review defects so every failed config persistence restores the previously owned routing and Codex agent state exactly enough for the persisted ownership record to remain valid.

**Architecture:** Lifecycle transitions use compensating routing reconciliation: after installing the next routing state, a failed save reconciles from that next state back to the previous profile and hosts before returning an error. The Codex preferred-model fallback uses an in-memory rewrite receipt containing a guarded rollback closure; it persists the new hash before retrying and restores the original owned file when persistence fails.

**Tech Stack:** Node.js 20+ ESM, `node:test`, atomic filesystem helpers, existing Fast Browser lifecycle and routing modules.

## Global Constraints

- Work only in `/Users/matt/Documents/GitHub/mattstack/.worktrees/fast-browser-dual-host`.
- Use strict red-green-refactor TDD and real disposable filesystem state for rollback assertions.
- Preserve unrelated user content in shared Codex TOML/Markdown containers.
- Never persist, log, return in CLI JSON, or attach to errors any captured file content.
- Never overwrite a routing file or block whose current ownership hash no longer matches the state being rolled back.
- Error messages and partial state remain path- and secret-redacted.
- Do not touch real Claude, Codex, Chrome, Keychain, or legacy migration state.
- Do not publish, push, or choose a license.

---

### Task 1: Restore prior routing after setup and migration persistence failures

**Files:**
- Modify: `plugins/fast-browser/lib/commands/setup.mjs`
- Modify: `plugins/fast-browser/lib/commands/migrate.mjs`
- Test: `plugins/fast-browser/tests/integration/lifecycle.test.mjs`
- Test: `plugins/fast-browser/tests/unit/commands.test.mjs`

**Interfaces:**
- Consumes: `installRouting({ profile, hosts, paths, codexVersion, managedState })`.
- Produces: setup and migration compensation that reconciles from the newly installed routing state back to `routingState(previousConfig)`.

- [ ] **Step 1: Add a failing real-filesystem setup transition test**

Create a prior full-profile Claude routing state in a disposable home, persist its config fixture, then run Claude-to-Codex setup with an injected `saveConfig` failure. Assert:

```js
assert.rejects(operation, ({ stage }) => stage === 'save-config');
assert.equal(await readFile(priorClaudeRule, 'utf8'), priorRuleBytes);
assert.equal(await readFile(priorClaudeConsent, 'utf8'), priorConsentBytes);
assert.deepEqual(await preflightRoutingRemoval({
  paths,
  managedState: routingState(previousConfig),
}), priorOwnershipSummary);
assert.rejects(access(codexAgent), { code: 'ENOENT' });
```

The test must retain unrelated text in any shared container it exercises.

- [ ] **Step 2: Run the setup test and verify RED**

Run:

```bash
node --test --test-name-pattern='setup restores prior routing' plugins/fast-browser/tests/integration/lifecycle.test.mjs
```

Expected: FAIL because the prior Claude routing files are absent after the injected save failure.

- [ ] **Step 3: Implement setup compensation**

Load the previous config before deciding whether Codex version detection is needed. Detect Codex when either the requested hosts or `selectedConfigHosts(previousConfig)` contains Codex. After the next routing is installed:

```js
if (previousConfig) {
  await installRouting({
    profile: previousConfig.profile,
    hosts: selectedConfigHosts(previousConfig),
    paths,
    codexVersion,
    managedState: nextRouting,
  });
} else {
  await removeRouting({ paths, managedState: nextRouting });
}
```

Use this compensation only after config persistence fails. If compensation also fails, return the existing recovery-required lifecycle error with only the next managed-state metadata.

- [ ] **Step 4: Add a failing real-filesystem migration cleanup test**

Create a prior Codex/full owned state plus unrelated shared-container text. Run the production migration composition with a later injected verification or persistence failure so `cleanupInstalled` executes. Assert the prior browser-driver bytes, policy block, routing block, unrelated content, and previous config are restored, while next-only Claude routing is absent.

- [ ] **Step 5: Run the migration test and verify RED**

Run:

```bash
node --test --test-name-pattern='migration cleanup restores prior routing' plugins/fast-browser/tests/unit/commands.test.mjs
```

Expected: FAIL because cleanup removes the next state and saves the previous config without reinstalling its routing.

- [ ] **Step 6: Implement migration compensation**

Keep these non-secret fields in the in-memory migration install state:

```js
{
  hadPreviousConfig,
  previousConfig,
  previousRouting: {
    profile,
    hosts,
    codexVersion,
  },
  managedState: nextRouting,
}
```

When cleanup has a previous config, call `installRouting` with the previous routing fields and `managedState: state.managedState`; otherwise call `removeRouting`. Save the previous config only after routing compensation succeeds. Preserve the recovery-required error path if compensation cannot be completed.

- [ ] **Step 7: Run focused and package tests**

Run:

```bash
node --test plugins/fast-browser/tests/integration/lifecycle.test.mjs plugins/fast-browser/tests/unit/commands.test.mjs plugins/fast-browser/tests/unit/routing.test.mjs
npm test --prefix plugins/fast-browser
git diff --check
```

Expected: all tests pass and both new tests prove prior ownership remains valid.

- [ ] **Step 8: Commit**

```bash
git add plugins/fast-browser/lib/commands/setup.mjs plugins/fast-browser/lib/commands/migrate.mjs plugins/fast-browser/tests/integration/lifecycle.test.mjs plugins/fast-browser/tests/unit/commands.test.mjs
git commit -m "fix(fast-browser): restore routing after failed persistence"
```

### Task 2: Roll back the Codex agent fallback when hash persistence fails

**Files:**
- Modify: `plugins/fast-browser/lib/hosts/routing.mjs`
- Modify: `plugins/fast-browser/lib/commands/doctor.mjs`
- Test: `plugins/fast-browser/tests/unit/routing.test.mjs`
- Test: `plugins/fast-browser/tests/unit/commands.test.mjs`

**Interfaces:**
- Produces: `beginOwnedCodexAgentFallback({ paths, managedState }): Promise<{ managedState, rollback(): Promise<void> }>` where the closure and captured bytes remain in memory only.
- Consumes: the existing `runWithCodexModelFallback` exactly-once retry contract.

- [ ] **Step 1: Add a failing routing-transaction test**

Create an owned preferred-model browser-driver file in a disposable home and call `beginOwnedCodexAgentFallback`. Assert the returned state hashes the rewritten file. Call `rollback()` and assert:

```js
assert.equal(await readFile(agentPath, 'utf8'), originalBytes);
assert.deepEqual(await preflightRoutingRemoval({
  paths,
  managedState: originalManagedState,
}), originalOwnershipSummary);
```

Then repeat after changing the rewritten file and assert rollback rejects with an ownership error without overwriting the external change.

- [ ] **Step 2: Run the routing test and verify RED**

Run:

```bash
node --test --test-name-pattern='Codex agent fallback transaction' plugins/fast-browser/tests/unit/routing.test.mjs
```

Expected: FAIL because `beginOwnedCodexAgentFallback` does not exist.

- [ ] **Step 3: Implement the guarded rewrite receipt**

The new function must:

1. perform the same confinement and original ownership checks as the existing rewrite;
2. retain original bytes only inside the returned closure;
3. atomically write the no-preferred-model bytes;
4. return the updated managed hash; and
5. on rollback, require the file to still match the updated hash before atomically restoring the original bytes.

Keep `rewriteOwnedCodexAgentWithoutPreferredModel` as a compatibility wrapper that returns only the receipt's `managedState`.

- [ ] **Step 4: Add a failing doctor save-failure test**

Run doctor with a specific preferred-model rejection, the production routing transaction against a disposable home, and an injected `saveConfig` failure. Assert:

```js
assert.equal(smokeAttempts, 1);
assert.equal(await readFile(agentPath, 'utf8'), originalBytes);
assert.equal(savedConfig, null);
assert.equal(browserDriverCheck.status, 'fail');
```

Also assert the old ownership state passes preflight and neither the check message nor serialized report contains captured bytes or a maintainer path.

- [ ] **Step 5: Run the doctor test and verify RED**

Run:

```bash
node --test --test-name-pattern='doctor restores the Codex agent when fallback config persistence fails' plugins/fast-browser/tests/unit/commands.test.mjs
```

Expected: FAIL because the preferred-model line remains removed after the save failure.

- [ ] **Step 6: Wire doctor to the transaction**

Use `beginOwnedCodexAgentFallback` in the fallback callback. Persist the returned managed hash. If persistence fails, call `rollback()` before rethrowing the redacted failure; do not update the in-memory config and do not retry the smoke. If rollback fails, surface a recovery-required check failure without captured content.

- [ ] **Step 7: Run focused and package tests**

Run:

```bash
node --test plugins/fast-browser/tests/unit/routing.test.mjs plugins/fast-browser/tests/unit/commands.test.mjs
npm test --prefix plugins/fast-browser
git diff --check
```

Expected: all tests pass; save failure restores old bytes/hash with one smoke attempt, while successful persistence still retries exactly once.

- [ ] **Step 8: Commit**

```bash
git add plugins/fast-browser/lib/hosts/routing.mjs plugins/fast-browser/lib/commands/doctor.mjs plugins/fast-browser/tests/unit/routing.test.mjs plugins/fast-browser/tests/unit/commands.test.mjs
git commit -m "fix(fast-browser): transact Codex fallback ownership"
```

### Task 3: Re-accept the corrected Plan 2 candidate

**Files:**
- Modify: `.superpowers/sdd/2026-07-26-fast-browser-transactional-recovery/progress.md`
- Create: `.superpowers/sdd/2026-07-26-fast-browser-transactional-recovery/final-review-package.md`

**Interfaces:**
- Consumes: both corrective commits and their task-review reports.
- Produces: a clean broad-review verdict and refreshed package/test evidence before Plan 3 begins.

- [ ] **Step 1: Run the final package suite from a clean worktree**

Run:

```bash
npm test --prefix plugins/fast-browser
python3 /Users/matt/.codex/skills/.system/plugin-creator/scripts/validate_plugin.py plugins/fast-browser
npm pack --dry-run --json --prefix plugins/fast-browser
git diff --check
git status --short
```

Expected: tests and validation pass, the package contains no secret/session/personal-path material, and tracked source is clean.

- [ ] **Step 2: Dispatch a broad independent review**

Review the complete corrective range against:

- exact restoration of prior routing/config after setup and migration persistence failure;
- guarded fallback rollback after doctor config persistence failure;
- preservation of unrelated shared-container content;
- redaction and ownership mismatch behavior; and
- regressions in the already-accepted selective-host, exact protocol 2, and exactly-once model fallback behavior.

- [ ] **Step 3: Record acceptance**

Append exact commit IDs, test counts, package file/byte counts, SHA-256, and the clean review verdict to the corrective ledger. Do not begin Plan 3 unless there are no open Critical or Important findings.
