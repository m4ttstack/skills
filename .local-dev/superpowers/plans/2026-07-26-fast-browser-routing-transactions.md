# Fast Browser Routing Transactions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace routing’s interleaved validation and mutation with a fully preflighted, fail-closed transaction that can restore either side of a lifecycle transition without re-rendering or overwriting unowned host configuration.

**Architecture:** Routing preparation reads every affected path once, validates all current ownership plus every desired destination, and computes one final before/after mutation per path without writing. Applying the prepared transition revalidates all snapshots, mutates deterministically, automatically reverses partial application failures, and returns a guarded reciprocal rollback receipt. Setup, configure, and migration keep receipts only in memory so persistence failures restore exact prior bytes without serializing file content or closures.

**Tech Stack:** Node.js 20+ ESM, `node:test`, `node:fs/promises`, SHA-256 ownership records, existing Fast Browser lifecycle and managed-block modules.

## Global Constraints

- Work only in `/Users/matt/Documents/GitHub/mattstack/.worktrees/fast-browser-dual-host`.
- Use strict red-green-refactor TDD; read `superpowers:test-driven-development` and `writing-good-tests.md` before changing tests.
- Preserve unrelated user bytes in shared Codex TOML and Markdown containers.
- Treat an unrecorded dedicated routing file as a conflict even when its bytes equal generated Fast Browser content.
- Treat an unrecorded Fast Browser block marker as a conflict even when its block hash equals generated Fast Browser content.
- Validate every affected target before the first mutation; a preparation or initial apply-preflight failure must leave every target byte-identical.
- Revalidate each target immediately before its mutation; a later failure must automatically reverse already-applied mutations or return a fixed recovery-required error.
- A guarded rollback must validate every applied target before the first reverse mutation and must never overwrite external drift.
- Keep captured bytes and rollback closures in memory only; never persist, log, serialize, return in CLI JSON, or attach them to errors or lifecycle partial state.
- Keep transaction errors path-, content-, and secret-redacted.
- Preserve the existing managed-state schema, safe/full profiles, Claude/Codex host selection, exact desired-state restoration, preferred Codex model behavior, and selective cleanup behavior.
- Keep `installRouting`, `removeRouting`, and `preflightRoutingRemoval` as compatibility exports backed by the transaction implementation.
- Do not touch real Claude, Codex, Chrome, Keychain, or legacy migration state.
- Do not publish, push, or choose a license.

---

### Task 1: Build the preflighted reciprocal routing transaction

**Files:**
- Create: `plugins/fast-browser/lib/hosts/file-transaction.mjs`
- Modify: `plugins/fast-browser/lib/hosts/routing.mjs`
- Test: `plugins/fast-browser/tests/unit/routing.test.mjs`
- Test: `plugins/fast-browser/tests/unit/file-transaction.test.mjs`

**Interfaces:**
- Produces:

```js
prepareFileTransaction({
  home,
  changes,
  io = nodeFileTransactionIo,
}): {
  apply(): Promise<{
    rollback(): Promise<ReciprocalReceipt>
  }>
}

// Each internal change is one consolidated path mutation.
{
  path: string,
  before: { exists: boolean, bytes: Buffer | null },
  after: { exists: boolean, bytes: Buffer | null }
}

prepareRoutingTransition({
  profile,
  hosts = ['claude', 'codex'],
  paths,
  codexVersion = '',
  managedState = null,
  desiredState = null,
  transactionIo,
}): Promise<{
  nextState: {
    profile: 'safe' | 'full',
    hosts: Array<'claude' | 'codex'>,
    files: Array<{ path: string, sha256: string }>,
    blocks: Array<{
      path: string,
      id: string,
      kind: 'markdown' | 'toml',
      sha256: string,
      containerCreated: boolean
    }>
  },
  apply(): Promise<ReciprocalReceipt>
}>
```

- `ReciprocalReceipt.rollback()` is single-use and returns a new reciprocal receipt whose `rollback()` restores the other side again.
- `nodeFileTransactionIo` is exported only from the internal transaction module so tests can wrap one mutation call and deterministically inject a failure.
- Consumes: existing Markdown/TOML parsers, routing templates, Codex agent renderer, confinement rules, and managed-state ownership hashes.

- [ ] **Step 1: Add failing filesystem transaction tests**

Create `tests/unit/file-transaction.test.mjs` using disposable homes. Cover:

```js
test('apply preflights every target before the first mutation', async () => {
  const prepared = prepareFileTransaction({ home, changes });
  await writeFile(secondPath, Buffer.from('external'));
  await assert.rejects(prepared.apply(), /routing transaction preflight failed/i);
  assert.equal(await readFile(firstPath, 'utf8'), 'before-one');
  assert.equal(await readFile(secondPath, 'utf8'), 'external');
});

test('apply automatically reverses each possible partial mutation failure', async () => {
  for (let failAt = 0; failAt < changes.length; failAt += 1) {
    const io = {
      ...nodeFileTransactionIo,
      async mutate(change) {
        if (mutationIndex++ === failAt) throw new Error('injected mutation failure');
        return nodeFileTransactionIo.mutate(change);
      },
    };
    await assert.rejects(
      prepareFileTransaction({ home, changes, io }).apply(),
      /routing transaction apply failed/i,
    );
    assert.deepEqual(await snapshotAll(paths), beforeSnapshots);
  }
});

test('rollback is guarded and reciprocal', async () => {
  const receipt = await prepareFileTransaction({ home, changes }).apply();
  const redo = await receipt.rollback();
  assert.deepEqual(await snapshotAll(paths), beforeSnapshots);
  await (await redo.rollback()).rollback();
  assert.deepEqual(await snapshotAll(paths), beforeSnapshots);
});
```

Also assert that external drift on any applied target makes `rollback()` reject before changing any other target, and that every thrown message omits target paths and file content.

- [ ] **Step 2: Run the transaction tests and verify RED**

Run:

```bash
node --test plugins/fast-browser/tests/unit/file-transaction.test.mjs
```

Expected: FAIL because `file-transaction.mjs` does not exist.

- [ ] **Step 3: Implement the generic transaction state machine**

Implement `file-transaction.mjs` with these rules:

```js
// Prepare:
// 1. reject duplicate paths, invalid before/after shapes, unconfined paths,
//    symlink leaves/parents, and non-regular leaves;
// 2. clone all buffers into closure-private snapshots;
// 3. sort changes by path for deterministic application;
// 4. return one single-use apply closure.

// Apply:
// 1. read and compare every current path to every before snapshot;
// 2. immediately before each mutation, compare that path again;
// 3. atomically write after bytes or unlink an existing path;
// 4. on failure, validate and reverse the applied prefix in reverse order;
// 5. return a receipt over the inverse snapshots.

// Rollback:
// Use the identical apply algorithm on inverse changes, so it is guarded,
// automatically recoverable, reciprocal, and single-use.
```

Create parent directories with mode `0700`, temporary files with mode `0600`, and atomic rename. Remove only exact regular-file leaves. Use fixed errors:

```js
'routing transaction preflight failed'
'routing transaction apply failed'
'routing transaction recovery required'
'routing transaction already consumed'
```

Never include a path, byte count, hash, original error message, or captured buffer in those errors.

- [ ] **Step 4: Run the transaction tests and verify GREEN**

Run:

```bash
node --test plugins/fast-browser/tests/unit/file-transaction.test.mjs
```

Expected: all transaction state-machine tests pass.

- [ ] **Step 5: Add failing routing ownership and consolidation tests**

Add real-filesystem tests to `routing.test.mjs` for:

1. an externally inserted `routing-v1` block at the exact `desiredState` Markdown destination;
2. an unrecorded policy block in `config.toml`;
3. an unrecorded dedicated browser-driver file whose bytes exactly equal the generated file;
4. drift in a later managed target while an earlier target is otherwise writable;
5. an AGENTS-to-AGENTS.override transition that removes the old owned block and installs the new block as one consolidated mutation per path;
6. injected failure at each routing mutation index, proving all paths return to their original snapshots;
7. exact prior-state restoration through the reciprocal receipt, including unrelated TOML/Markdown bytes and `containerCreated` provenance.

The load-bearing regression must use this shape:

```js
const prior = await installRouting({ profile: 'full', paths });
const desiredState = structuredClone(prior);
await removeRouting({ paths, managedState: prior });
await writeFile(recordedAgentsPath, [
  'external',
  '<!-- fast-browser:start routing-v1 -->',
  'not owned',
  '<!-- fast-browser:end routing-v1 -->',
].join('\n'));

const operation = prepareRoutingTransition({
  profile: 'full',
  paths,
  managedState: null,
  desiredState,
});
await assert.rejects(operation, /routing block destination conflict/i);
assert.equal(await readFile(recordedAgentsPath, 'utf8'), externalBytes);
```

- [ ] **Step 6: Run the routing tests and verify RED**

Run:

```bash
node --test --test-name-pattern='transaction|unrecorded|desired destination|consolidates' plugins/fast-browser/tests/unit/routing.test.mjs
```

Expected: at least the desired-destination test FAILS because `installRouting` currently replaces the unowned block before exact-state validation.

- [ ] **Step 7: Refactor routing preparation around one path snapshot map**

Move filesystem mutation ownership to `file-transaction.mjs`. In `routing.mjs`, implement these preparation phases before calling `prepareFileTransaction`:

```js
// A. Validate profile, hosts, managedState, desiredState, and confinement.
// B. Snapshot every union target exactly once.
// C. Validate all managed dedicated hashes and managed block hashes.
// D. Resolve desired dedicated files and shared blocks.
// E. Require every desired-but-unmanaged dedicated leaf to be absent.
// F. Require every desired-but-unmanaged marker identity to be absent.
// G. Starting from each original snapshot, remove no-longer-desired owned
//    records and render desired owned records entirely in memory.
// H. Validate exact desiredState records against rendered records.
// I. Emit at most one before/after change per path.
```

For a desired identity already present in `managedState`, allow absence or require the current recorded hash before replacement. For a desired identity absent from `managedState`, require the marker to be absent before rendering. Preserve unrelated container bytes. Delete an empty shared container only when its removed record proves Fast Browser created it and no desired content remains.

Implement:

```js
export async function prepareRoutingTransition(options) {
  const { nextState, changes } = await prepareRoutingChanges(options);
  const transaction = prepareFileTransaction({
    home: targetsFor(options.paths).home,
    changes,
    ...(options.transactionIo ? { io: options.transactionIo } : {}),
  });
  return Object.freeze({
    nextState,
    apply: transaction.apply,
  });
}

export async function installRouting(options) {
  const prepared = await prepareRoutingTransition(options);
  await prepared.apply();
  return prepared.nextState;
}

export async function removeRouting({ paths, managedState, transactionIo }) {
  const prepared = await prepareRoutingRemoval({
    paths,
    managedState,
    transactionIo,
  });
  await prepared.apply();
}
```

Keep `preflightRoutingRemoval` returning the existing non-secret existence summary. It may share the prepared snapshots, but it must not mutate and must not expose bytes.

- [ ] **Step 8: Run focused and package tests**

Run:

```bash
node --test plugins/fast-browser/tests/unit/file-transaction.test.mjs plugins/fast-browser/tests/unit/routing.test.mjs
npm test
git diff --check
```

Expected: all tests pass; the package suite remains at least 273 tests plus the new transaction cases.

- [ ] **Step 9: Commit**

```bash
git add plugins/fast-browser/lib/hosts/file-transaction.mjs plugins/fast-browser/lib/hosts/routing.mjs plugins/fast-browser/tests/unit/file-transaction.test.mjs plugins/fast-browser/tests/unit/routing.test.mjs
git commit -m "refactor(fast-browser): transact routing mutations"
```

### Task 2: Use exact routing receipts in setup and configure

**Files:**
- Modify: `plugins/fast-browser/lib/commands/setup.mjs`
- Modify: `plugins/fast-browser/lib/commands/configure.mjs`
- Test: `plugins/fast-browser/tests/integration/lifecycle.test.mjs`
- Test: `plugins/fast-browser/tests/unit/commands.test.mjs`

**Interfaces:**
- Consumes: `prepareRoutingTransition(options)` and its `{ nextState, apply() }` result from Task 1.
- Produces: setup/configure lifecycle code that applies once and calls the returned guarded receipt on persistence failure.
- The receipt remains a local variable and is never placed in `LifecycleError.partialState`, command results, config, JSON, or logs.

- [ ] **Step 1: Add failing setup receipt tests**

Update setup dependency fixtures to inject `prepareRoutingTransition`. Add tests that record:

```js
[
  'routing:prepare',
  'routing:apply',
  'config:save',
  'routing:rollback',
]
```

On injected config-save failure, assert exact prior filesystem snapshots are restored without a second prepare/render call. Add external drift after apply but before save failure and assert setup returns the existing recovery-required stage without overwriting drift or exposing a receipt/path/content in serialized error state.

- [ ] **Step 2: Run the setup tests and verify RED**

Run:

```bash
node --test --test-name-pattern='setup.*routing receipt|setup.*exact prior' plugins/fast-browser/tests/integration/lifecycle.test.mjs plugins/fast-browser/tests/unit/commands.test.mjs
```

Expected: FAIL because setup compensates by calling `installRouting` or `removeRouting` a second time.

- [ ] **Step 3: Wire setup to the prepared transaction**

Replace the default routing dependency with `prepareRoutingTransition`. Use:

```js
const preparedRouting = await deps.prepareRoutingTransition({
  profile,
  hosts,
  paths: deps.paths,
  codexVersion,
  managedState: current ? routingState(current) : null,
});
routing = preparedRouting.nextState;
routingReceipt = await preparedRouting.apply();
```

On config persistence failure, call `await routingReceipt.rollback()` exactly once. Preserve the existing fixed success, rollback-success, and recovery-required lifecycle messages/stages. Remove setup’s `desiredState` compensation path and prior Codex-version reconstruction used only for that compensation.

- [ ] **Step 4: Add failing configure receipt tests**

For plain, automatic, and manual configuration persistence failures, assert routing is prepared/applied once and rolled back once. Assert successful persistence never invokes rollback. Use a real disposable routing state for one test and verify both prior ownership and unrelated shared-container bytes after rollback.

- [ ] **Step 5: Run the configure tests and verify RED**

Run:

```bash
node --test --test-name-pattern='configure.*routing receipt|configure.*exact prior' plugins/fast-browser/tests/unit/commands.test.mjs
```

Expected: FAIL because configure reconciles routing by rendering the old profile again.

- [ ] **Step 6: Wire configure to the prepared transaction**

Prepare and apply before building the next config:

```js
const preparedRouting = await deps.prepareRoutingTransition({
  profile,
  hosts,
  paths: deps.paths,
  codexVersion,
  managedState: routingState(current),
});
managedState = preparedRouting.nextState;
const routingReceipt = await preparedRouting.apply();
```

In the existing persistence/pairing catch, call `routingReceipt.rollback()` exactly once. Preserve `PairingError` behavior after a successful rollback and preserve the recovery-required lifecycle error when rollback rejects. Do not include the receipt in returned or thrown state.

- [ ] **Step 7: Run focused and package tests**

Run:

```bash
node --test plugins/fast-browser/tests/integration/lifecycle.test.mjs plugins/fast-browser/tests/unit/commands.test.mjs plugins/fast-browser/tests/unit/routing.test.mjs plugins/fast-browser/tests/unit/file-transaction.test.mjs
npm test
git diff --check
```

Expected: all tests pass and no setup/configure save-failure path re-renders routing.

- [ ] **Step 8: Commit**

```bash
git add plugins/fast-browser/lib/commands/setup.mjs plugins/fast-browser/lib/commands/configure.mjs plugins/fast-browser/tests/integration/lifecycle.test.mjs plugins/fast-browser/tests/unit/commands.test.mjs
git commit -m "fix(fast-browser): roll back routing receipts"
```

### Task 3: Keep migration routing receipts private and reciprocal

**Files:**
- Modify: `plugins/fast-browser/lib/commands/migrate.mjs`
- Modify: `plugins/fast-browser/lib/migration/apply.mjs`
- Test: `plugins/fast-browser/tests/unit/commands.test.mjs`
- Test: `plugins/fast-browser/tests/integration/lifecycle.test.mjs`

**Interfaces:**
- Consumes: `prepareRoutingTransition(options)` and reciprocal receipts from Task 1.
- Produces: a module-private `WeakMap<object, ReciprocalReceipt>` keyed by the exact in-memory installed-state object.
- `installAdaptersAndRouting()` returns only redacted metadata; `cleanupInstalled(state)` looks up the receipt by object identity.

- [ ] **Step 1: Add failing migration receipt and redaction tests**

Add tests for:

1. verification failure after next config persistence restores the prior routing and prior config through one receipt rollback;
2. next-config save failure restores prior routing without trying to re-save an already persisted prior config;
3. failure to restore the prior config uses the reciprocal receipt to restore the next routing so it still matches the persisted next config;
4. external drift before receipt rollback produces the fixed recovery-required stage without overwriting drift;
5. serialized install state, thrown partial state, and JSON output contain no function, captured bytes, receipt property, target path, or template content.

The reciprocal recovery sequence must assert:

```js
assert.deepEqual(events, [
  'routing:prepare-next',
  'routing:apply-next',
  'config:save-next',
  'verify:fail',
  'routing:rollback-to-prior',
  'config:save-prior:fail',
  'routing:rollback-to-next',
]);
```

- [ ] **Step 2: Run the migration tests and verify RED**

Run:

```bash
node --test --test-name-pattern='migration.*receipt|migration.*reciprocal|migration.*private' plugins/fast-browser/tests/unit/commands.test.mjs plugins/fast-browser/tests/integration/lifecycle.test.mjs
```

Expected: FAIL because migration cleanup reconstructs both routing states with `installRouting` and serializable desired-state metadata.

- [ ] **Step 3: Apply and privately retain the next routing receipt**

In migration composition:

```js
const routingReceipts = new WeakMap();

const prepared = await prepareOwnedRouting({
  profile: previousConfig.profile,
  hosts,
  paths,
  codexVersion,
  managedState: routingState(previousConfig),
});
state.managedState = prepared.nextState;
const receipt = await prepared.apply();
routingReceipts.set(state, receipt);
```

Keep `state` restricted to existing non-secret metadata. Do not add the receipt, reciprocal receipt, bytes, path snapshots, or closures to `state` or `safeError.partialState`.

- [ ] **Step 4: Replace reconstruction cleanup with reciprocal rollback**

In `cleanupInstalled(state)`:

```js
const receipt = routingReceipts.get(state);
if (receipt) {
  const redo = await receipt.rollback();
  if (state.configPersisted) {
    try {
      await saveConfig(paths, state.previousConfig);
    } catch {
      await redo.rollback();
      return;
    }
  }
}
```

After prior routing/config restoration succeeds, remove only adapters installed by this migration. When no previous config existed, the same receipt restores the exact absent/previous filesystem state. If guarded rollback or reciprocal reapply fails, let the migration layer return its fixed recovery-required error. Delete the WeakMap entry after terminal cleanup.

- [ ] **Step 5: Preserve cleanup identity through the migration engine**

Verify `applyMigration` passes the original installed-state object, or the identical `cause.partialState` object when installation throws after apply, to `cleanupInstalled`. Change only the selection logic needed to preserve identity; do not clone, spread, serialize, or decorate the state.

- [ ] **Step 6: Run focused and package tests**

Run:

```bash
node --test plugins/fast-browser/tests/unit/commands.test.mjs plugins/fast-browser/tests/integration/lifecycle.test.mjs plugins/fast-browser/tests/unit/routing.test.mjs plugins/fast-browser/tests/unit/file-transaction.test.mjs
npm test
git diff --check
```

Expected: all tests pass; persisted prior and next config states always retain their matching routing unless a fixed recovery-required error reports external drift.

- [ ] **Step 7: Commit**

```bash
git add plugins/fast-browser/lib/commands/migrate.mjs plugins/fast-browser/lib/migration/apply.mjs plugins/fast-browser/tests/unit/commands.test.mjs plugins/fast-browser/tests/integration/lifecycle.test.mjs
git commit -m "fix(fast-browser): transact migration routing recovery"
```

## Acceptance Gates

- Run the complete package suite with loopback permission and record the exact test count.
- Run the plugin validator and `npm pack --dry-run --json`.
- Confirm `git diff --check` and a clean task diff.
- Run a broad independent review over the complete plan commit range.
- Do not resume real-host Plan 3 E2E until no Critical or Important findings remain.
