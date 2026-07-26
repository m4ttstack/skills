# Fast Browser Dual-Host Plugin Design

**Status:** Approved

**Date:** 2026-07-25

**Initial platform:** macOS + Google Chrome

**Hosts:** Claude Code and Codex

## Summary

Fast Browser will be a single installable product in `mattstack` that gives
Claude Code and Codex the same fast Playwright browser-driving workflow.

The product consists of:

1. one plugin directory that contains both host manifests;
2. shared browser skills and macro behavior;
3. thin host adapters for MCP configuration, routing, and browser-driver agents;
4. a setup and diagnostics CLI;
5. a dedicated Chrome extension; and
6. a pinned Playwright MCP runtime built from the existing
   `m4ttheweric/playwright` fork.

Public installations use conservative defaults. Matt's installation uses an
explicit `full` profile that reproduces the current Claude Code behavior in
both hosts.

## Context

Matt's current Claude Code setup combines:

- a Playwright MCP fork launched with extension mode, no automatic snapshots,
  session saving, and a 200 ms settle delay;
- a browser-driver subagent for multi-step browser work;
- routing and browser-verification consent rules;
- fast-browsing, browser-macros, and macro-mining skills; and
- a Chrome extension token stored directly in host configuration.

The Playwright fork adds capabilities that are not all available upstream:

- concurrent extension clients with independent Chrome tab groups;
- workspace labels on client tab groups;
- no focus stealing between clients;
- skipping accessibility snapshot generation when the response discards it;
- a configurable post-action settle delay; and
- filename plus argument support for `browser_run_code_unsafe`.

The setup works well for one machine but is not distributable. It contains
machine-specific paths, a secret in configuration, host-specific assumptions,
and no repeatable installer, updater, diagnostics, migration, or release
process.

## Goals

### Product goals

- Install one Fast Browser product for Claude Code, Codex, or both.
- Preserve the current fast browser loop and macro behavior in both hosts.
- Connect to the user's existing logged-in Chrome session.
- Support simultaneous Claude Code and Codex clients without focus stealing.
- Keep shared behavior in one source of truth.
- Make installation, upgrades, diagnostics, migration, and removal repeatable.
- Keep secrets and recorded browser data local.
- Ship no machine-specific paths or personal browser data.

### User-experience goals

- A new user can run one setup command and receive actionable guidance through
  every remaining manual Chrome step.
- The normal browser loop avoids implicit page snapshots.
- Multi-step browser tasks can run in a focused browser-driver agent and return
  only distilled results.
- Known macros execute in one browser call with explicit arguments.
- A broken installation can be diagnosed without reading host config by hand.
- Uninstall is reversible and does not delete user macros unless explicitly
  requested.

## Non-goals for v1

- Windows or Linux.
- Firefox, WebKit, Safari, or remote browser hosts.
- Cloud-hosted MCP or ChatGPT support.
- Silent installation of an unpacked Chrome extension.
- A public macro marketplace.
- Automatic installation of mined macros.
- Removing users' other browser plugins or tools.
- Editing project-level `CLAUDE.md` or `AGENTS.md` files.
- Upstreaming every Playwright patch before the first release.

## Primary Decision

Build **one dual-host plugin plus a setup CLI**.

The same physical plugin directory will contain:

- `.claude-plugin/plugin.json` for Claude Code;
- `.codex-plugin/plugin.json` for Codex;
- shared `skills/`;
- the Claude Code browser-driver agent;
- a Codex browser-driver template installed by the CLI;
- host-specific MCP descriptors that launch the same wrapper; and
- the setup, runtime-launch, diagnostics, migration, and uninstall code.

Claude and Codex marketplace entries will both point to this directory. A
single product version covers the plugin, CLI compatibility contract, runtime
lock, extension compatibility, and shared skills.

This avoids two plugins drifting while respecting the fact that the hosts use
different manifest, agent, and durable-instruction formats.

## Source and Release Boundaries

### `mattstack`

`mattstack` owns the Fast Browser product and is the canonical source for:

- the dual-host plugin package;
- shared skills;
- host adapters;
- the setup and diagnostics CLI;
- configuration and data schemas;
- migration logic;
- marketplace metadata;
- release locks and checksums;
- tests and deterministic browser fixtures; and
- user documentation.

### `m4ttheweric/playwright`

The existing Playwright fork remains the canonical source for:

- Playwright MCP runtime changes;
- Chrome extension multi-client behavior;
- focus and tab-group behavior;
- snapshot-generation optimizations;
- settle-timeout support; and
- filename-and-arguments macro execution.

Its release automation produces versioned runtime and extension artifacts.
`mattstack` consumes those artifacts through `runtime-lock.json`, which records
the package or artifact version, source commit, compatibility version, and
SHA-256.

The plugin must not clone or build the full Playwright repository during normal
setup or MCP startup.

### Upstream relationship

Patches should be proposed upstream when practical, but the product must not
depend on an uncertain upstream merge schedule. When upstream gains equivalent
behavior, the lock may move from the forked artifact to the upstream package
without changing the host-facing plugin contract.

## Proposed Repository Layout

```text
mattstack/
├── plugins/
│   └── fast-browser/
│       ├── .claude-plugin/
│       │   └── plugin.json
│       ├── .codex-plugin/
│       │   └── plugin.json
│       ├── .mcp.json
│       ├── adapters/
│       │   └── codex/
│       │       └── mcp.json
│       ├── agents/
│       │   └── browser-driver.md
│       ├── bin/
│       │   └── fast-browser.mjs
│       ├── builtins/
│       │   └── macros/
│       │       └── page-recon.js
│       ├── lib/
│       │   ├── cli/
│       │   ├── config/
│       │   ├── host-adapters/
│       │   ├── keychain/
│       │   ├── migration/
│       │   └── runtime/
│       ├── skills/
│       │   ├── fast-browsing/
│       │   ├── browser-macros/
│       │   └── mine-macros/
│       ├── templates/
│       │   ├── codex/
│       │   │   └── browser_driver.toml
│       │   └── routing/
│       │       ├── claude/
│       │       └── codex/
│       ├── tests/
│       │   ├── fixtures/
│       │   ├── integration/
│       │   ├── unit/
│       │   └── e2e/
│       ├── package.json
│       ├── runtime-lock.json
│       └── README.md
├── skills/
│   └── browser/
│       └── ... compatibility links during migration
└── ... host marketplace catalogs
```

The existing `skills/browser/*` content moves into the plugin and becomes
host-neutral. Transitional repository-relative compatibility links keep Matt's
current local skill symlinks working until the setup CLI completes migration.
Packaged plugin artifacts contain only real files and never depend on paths
outside the plugin root.

## Component Design

### Dual manifests

Claude Code reads `.claude-plugin/plugin.json`. Codex reads
`.codex-plugin/plugin.json`. Both declare the same name, semantic version,
description, repository, license metadata, and shared skills directory.

The plugin root contains two MCP descriptors because the currently documented
wrapper shapes differ:

- root `.mcp.json` uses Claude Code's `mcpServers` shape and
  `${CLAUDE_PLUGIN_ROOT}`;
- `adapters/codex/mcp.json` uses Codex's accepted server-map shape and the
  Codex plugin-root substitution; and
- the Codex manifest points its `mcpServers` field at the adapter descriptor.

Both descriptors invoke the same plugin-local runtime wrapper. Neither contains
a pairing token or a user-specific absolute path.

### Runtime wrapper

Every host launches the plugin-local wrapper. The wrapper:

1. loads and validates `~/.fast-browser/config.json`;
2. resolves the pinned runtime from `~/.fast-browser/runtime/<version>/`;
3. verifies the artifact checksum when installed or updated;
4. reads an extension token from macOS Keychain only in auto-connect mode;
5. creates required data directories with mode `0700`;
6. launches the Playwright MCP runtime with the selected profile; and
7. translates startup failures into short, actionable diagnostics.

The full profile launches with behavior equivalent to the current setup:

- Chrome extension mode enabled;
- `snapshot-mode=none`;
- settle timeout set to 200 ms;
- session saving enabled;
- shared output directory under `~/.fast-browser/`; and
- the workspace label supplied when the host makes it available.

The safe profile uses the same performance settings but disables session saving
and persistent auto-connect.

MCP startup performs no dependency installation and no release download. If a
runtime is absent, the wrapper exits with a command telling the user to run
`fast-browser setup` or `fast-browser doctor`.

### Chrome extension

Fast Browser uses its own extension identity rather than depending on the
Microsoft Playwright MCP extension's published ID.

The v1 extension is built from the fork and supports:

- multiple concurrent local MCP clients;
- one labeled tab group per client;
- no focus stealing;
- an explicit list of connected clients;
- manual connection approval; and
- optional token-based automatic reconnect.

Before a Chrome Web Store listing is available, setup downloads and verifies an
unpacked extension artifact, opens `chrome://extensions`, and gives exact
developer-mode installation steps. Chrome still requires the user to perform
the final installation action.

After a store listing exists, setup opens that listing and verifies the
installed extension ID and compatible version.

### Shared skills

The three existing browser skills become host-neutral:

- `fast-browsing`: macro-first, scout once, batch the known flow, and read only
  targeted state;
- `browser-macros`: match, invoke, validate, and record failures; and
- `mine-macros`: find repeated flows and propose macros with an explicit
  per-macro approval gate.

All references use `~/.fast-browser/` or paths relative to the installed plugin.
No skill references `~/.claude`, `~/.codex`, `/Users/matt`, or the local
checkout.

The initial public built-in macro library contains only a generic,
origin-neutral `page-recon` macro. Matt's personal macros are imported locally
and are never committed or published.

### Macro contract

User macros live in `~/.fast-browser/macros/`.

Each macro:

- exports or evaluates to `async (page, args) => result`;
- validates required arguments;
- derives its own locators;
- contains its own condition-based waits;
- returns a small result proving success;
- catches failures by logical step; and
- returns `{ failedStep, error, url }` on expected failure.

`browser_run_code_unsafe` accepts `{ filename, args }`. Runtime file access is
restricted to approved runtime roots, including the Fast Browser data
directory. A macro failure is recorded in
`~/.fast-browser/macro-failures.md`. Two failures on the same attempt trigger
step-mode recovery rather than repeated blind macro execution.

Macro mining remains local. It may propose a script, but it cannot write the
macro library or mark a macro approved until the user explicitly approves that
individual proposal.

## Host Parity Contract

Parity means the same observable browser behavior, not identical host files.

### Shared behavior

Both hosts must:

1. use Fast Browser for an explicit Fast Browser request;
2. use the fast-browsing skill for multi-step Playwright work;
3. check the macro index before deriving a known flow;
4. delegate multi-step work to a focused browser-driver agent when the host
   supports that workflow;
5. avoid implicit snapshots;
6. batch known steps into compact Playwright code;
7. request a semantic snapshot only when DOM state is needed;
8. use screenshots only when the evidence is genuinely visual;
9. preserve browser focus when another client is active; and
10. return distilled results instead of the browser transcript.

### Browser-driver agents

Claude Code receives `agents/browser-driver.md` from the plugin.

Codex receives `~/.codex/agents/browser_driver.toml` from a versioned template
installed by the CLI. The agent file includes the Fast Browser MCP server,
focused browser-driving instructions, and medium reasoning effort. The default
Codex model is the currently supported fast subagent model
`gpt-5.6-terra`; setup must validate that value and fall back to inherited host
configuration when it is unavailable. The Claude agent uses Claude Code's
current `sonnet` alias rather than a dated model ID.

Both agents:

- own multi-step browser execution;
- may use macros and unsafe page code within the configured approval policy;
- avoid unrelated code or repository changes; and
- return the result, compact evidence, and any unresolved failure.

Simple one-step browser reads may remain in the parent agent when delegation
would cost more than the operation.

### Routing profiles

#### Safe profile

The default public profile:

- activates on explicit Fast Browser invocation or a clear browser-driving
  request;
- does not install global Playwright-first instructions;
- leaves every existing browser plugin installed;
- requires manual extension connection approval;
- disables session recording and macro mining inputs; and
- keeps state-changing or arbitrary page-code tools visibly privileged.

#### Full profile

`fast-browser setup --profile full` reproduces Matt's current power-user
behavior:

- browser-driving tasks route to Fast Browser by default;
- multi-step work delegates to the browser-driver agent;
- other browser tools remain installed but are not selected unless the user
  explicitly requests them;
- the extension reconnects with a Keychain-stored token;
- session saving is enabled; and
- self-initiated visual verification asks first unless the user explicitly
  requested browser verification or an active skill authorizes it.

Claude Code receives dedicated, CLI-owned files under `~/.claude/rules/`.

Codex receives a clearly delimited, idempotent managed block in the active
global instruction file. The CLI chooses `~/.codex/AGENTS.override.md` when it
exists and otherwise uses `~/.codex/AGENTS.md`, matching Codex's instruction
precedence. It never modifies a repository's `AGENTS.md`.

The CLI records every managed target and exact inserted content so reconfigure
and uninstall can remove only Fast Browser-owned data.

## Installation and Lifecycle

### Commands

The intended public entry point is:

```sh
npx @mattstack/fast-browser setup
```

The CLI also exposes:

```text
fast-browser setup [--host claude|codex|both] [--profile safe|full]
fast-browser doctor [--json]
fast-browser configure
fast-browser migrate
fast-browser uninstall [--host claude|codex|both] [--purge-data]
```

The npm scope and final package name must be confirmed before public release,
but the command contract remains the same if the package name changes.

### Setup flow

Setup:

1. verifies macOS, Node.js, Google Chrome, and supported host CLI versions;
2. detects Claude Code and Codex;
3. asks which detected hosts to configure, defaulting to both when both exist;
4. asks for `safe` or `full`, defaulting to `safe`;
5. installs or updates both marketplace adapters from the same plugin root;
6. downloads and verifies the pinned MCP runtime and extension artifact;
7. guides extension installation or store installation;
8. pairs Chrome manually or runs the opt-in auto-connect flow;
9. installs the Codex browser-driver template;
10. installs profile-specific routing files;
11. imports recognized legacy data when present; and
12. runs `doctor` and a harmless live-page smoke test.

No step requires `sudo`. Setup does not edit the current project.

### Pairing

Manual approval is the default and requires no saved token.

Auto-connect is explicit. The extension and CLI complete a local pairing flow,
and the resulting random secret is stored in macOS Keychain under a
Fast Browser-specific service and account. Host config, plugin files,
`~/.fast-browser/config.json`, logs, and diagnostics never print or persist the
secret.

The runtime receives the token only for the lifetime of its process.

### Doctor

`doctor` reports each layer independently:

- host CLI availability and version;
- marketplace and plugin installation;
- managed routing file status;
- browser-driver agent status;
- runtime version, source commit, and checksum;
- extension ID and version;
- Chrome availability;
- pairing mode and Keychain item presence, never its value;
- MCP initialization;
- expected tool inventory;
- session and macro directory permissions; and
- an optional two-client concurrency test.

Human output includes remediation commands. `--json` returns a stable schema
for E2E tests and support reports.

### Configure and uninstall

`configure` may change hosts, profile, connection mode, session recording, and
retention without reinstalling unrelated components.

`uninstall`:

- removes only selected host registrations and Fast Browser-owned routing
  content;
- removes the CLI-managed Codex agent only when no configured Codex adapter
  needs it;
- removes the Keychain item after confirmation;
- removes downloaded runtimes and extension artifacts when unused; and
- preserves macros, sessions, and backups by default.

`--purge-data` is explicit and reports exactly which Fast Browser directory
will be removed before deletion.

## Local Data Model

```text
~/.fast-browser/
├── config.json
├── runtime/
│   └── <version>/
├── extension/
│   └── <version>/
├── macros/
│   ├── MACROS.md
│   └── *.js
├── macro-failures.md
├── sessions/
├── archive/
└── backups/
```

The root directory is mode `0700`. Files containing configuration, recordings,
or migration manifests are mode `0600` unless they must be executable.

`config.json` is versioned by `schemaVersion` and contains settings and
installation state, not secrets. Host adapter state includes enough
information to reverse only Fast Browser's mutations.

Session recording is off in `safe` and on in `full`. Recorded pages can contain
sensitive URLs and page text, so setup shows that warning before enabling the
feature. Retention defaults to 30 days when recording is enabled and is
configurable. Macro mining archives processed sessions and applies the same
retention policy.

Fast Browser sends no telemetry by default.

## Security and Consent

Fast Browser controls an already authenticated Chrome session. Its effective
authority is the user's authority in that browser. The installer and README
must state this plainly.

Security requirements:

- extension connections require explicit approval or a Keychain-backed token;
- all runtime artifacts are version-pinned and checksum-verified;
- no secret appears in a manifest, command line persisted by a host, log,
  support bundle, or repository;
- browser output is treated as untrusted content;
- arbitrary page-code execution is never annotated as read-only;
- safe-profile host policy prompts for privileged browser execution according
  to host capabilities;
- a full-profile user may grant scoped trust during setup, but the tool remains
  accurately classified;
- macros never auto-publish;
- session logs are opt-in for public users;
- plugin startup performs no unexpected network install; and
- plugin, fork, and extension releases include applicable license and notice
  files.

The maintainer must select a license for the new mattstack product before
public release. Forked Playwright code and artifacts retain upstream
Apache-2.0 notices and source attribution.

## Migration from Matt's Current Setup

Migration is additive until the new setup passes end to end.

### Inventory

The migrator detects only recognized Fast Browser resources:

- the Playwright MCP entry in Claude configuration;
- Fast Browser-specific Claude rules;
- the browser-driver agent;
- mattstack browser skill symlinks;
- `~/.playwright-mcp/` macros, failure records, sessions, and archive; and
- the current extension connection settings.

It records file identity and relevant hashes before changing anything. It
never copies or displays the existing token in a report.

### Install beside the legacy setup

The CLI installs the dual-host plugin, runtime, extension, Codex agent, and
profile routing without deleting the old files. It copies browser data into
`~/.fast-browser/`, preserving the source tree.

Imported macro index entries are rewritten to portable
`~/.fast-browser/macros/` paths. Personal benchmark macros are imported for
Matt but excluded from the distributable plugin.

### Verify and switch

Migration runs:

- Claude Code plugin validation and MCP smoke tests;
- Codex plugin validation and MCP smoke tests;
- the same deterministic E2E fixture in both hosts;
- simultaneous two-client Chrome attachment; and
- a focus-preservation check.

Only after all required checks pass does the CLI remove recognized legacy host
registrations and symlinks. It does not delete `~/.playwright-mcp/`.

The migration report includes a generated rollback command that restores
Fast Browser-owned host configuration from the recorded pre-migration state.

## Testing Strategy

### Unit tests

Unit tests cover:

- config parsing, migrations, and rejection of unknown destructive targets;
- runtime lock parsing and checksum verification;
- macOS path resolution without hardcoded home paths;
- Keychain command construction with redacted output;
- host detection;
- Claude MCP generation;
- Codex MCP generation;
- managed-block insertion, update, and removal;
- preservation of unrelated user configuration;
- macro path rewriting;
- setup and uninstall idempotence; and
- `doctor --json` schema stability.

### Plugin validation

Every release runs:

- Claude Code plugin validation;
- Codex plugin and marketplace validation;
- manifest version-consistency checks;
- a packaged-artifact check proving all referenced paths remain inside the
  plugin root; and
- a secret and absolute-maintainer-path scan.

### MCP integration

Integration tests:

- initialize the MCP server without Chrome and confirm a useful connection
  state;
- enumerate the expected tools;
- audit tool annotations, especially `browser_run_code_unsafe`;
- connect to the test extension;
- execute snapshot-free actions;
- explicitly request a semantic snapshot;
- run a filename-and-arguments macro; and
- verify session behavior for both profiles.

### Extension concurrency

A real Chrome E2E test connects two clients representing Claude Code and Codex.
It verifies:

- both clients stay connected;
- each receives a distinct labeled tab group;
- one client's actions do not move focus to the other's group;
- disconnecting one client does not break the other; and
- reconnecting retains the correct client identity.

### Cross-host E2E

A deterministic local fixture contains a five-step flow with navigation,
inputs, conditional UI, and a final verifiable result.

The harness executes the same request through Claude Code and Codex and asserts:

- task success;
- the same final browser state;
- no more than eight browser tool calls for the fast loop;
- one browser tool call when a matching macro is used;
- no implicit semantic snapshots; and
- distilled final output rather than page dumps.

Wall-clock time is recorded as a regression signal rather than a hard CI gate
because model and host latency vary. A greater-than-20-percent regression
against the rolling baseline requires release review.

Public CI uses a clean test Chrome profile and never depends on a maintainer's
logged-in sites.

## Release Process

One Fast Browser semantic version coordinates:

- the dual-host plugin;
- CLI behavior and configuration schema;
- shared skills;
- runtime compatibility;
- extension compatibility; and
- marketplace metadata.

The runtime and extension can have their own artifact versions, but the plugin's
`runtime-lock.json` chooses the exact compatible pair.

A release:

1. builds runtime, extension, CLI, and plugin artifacts;
2. records source commits and SHA-256 values;
3. validates both host manifests;
4. runs unit, integration, concurrency, cross-host, and performance checks;
5. publishes the CLI/runtime packages and GitHub release artifacts;
6. updates both marketplace catalogs to the same plugin directory and version;
7. publishes or updates the Chrome Web Store listing when available; and
8. tests a clean install, upgrade, migration, rollback, and uninstall on macOS.

Until npm and Chrome Web Store publishing are configured, alpha releases may
use a pinned GitHub release and unpacked extension. They must still use the same
checksums, manifests, data locations, and command behavior as the public
release.

## Failure Handling

- A missing Chrome extension is a setup state, not an MCP crash loop.
- A pairing failure tells the user whether approval, extension version, or
  Keychain state is responsible.
- A runtime checksum mismatch quarantines the artifact and refuses to launch.
- A host config conflict stops before mutation and reports the exact file.
- A failed migration leaves the legacy setup active.
- A failed full-profile routing update rolls back only the managed content.
- A macro failure returns its logical step and current URL.
- An unavailable preferred browser-driver model falls back to host inheritance
  and is reported by `doctor`.

## Acceptance Criteria

The initial release is complete when:

1. one plugin directory validates and installs in both Claude Code and Codex;
2. setup configures either or both hosts on a clean macOS account without
   machine-specific edits;
3. no token, personal path, session, or personal macro ships in the artifact;
4. safe and full profiles behave as specified;
5. both hosts connect simultaneously to the same Chrome installation without
   focus stealing;
6. both hosts pass the same deterministic E2E flow;
7. the fast loop and macro call-count budgets pass;
8. `doctor` identifies failures at each layer with an actionable remedy;
9. setup, update, migration, rollback, and uninstall preserve unrelated user
   state and are idempotent;
10. Matt's current Claude browser behavior is preserved after migration and is
    available in Codex; and
11. release artifacts include the selected mattstack license and all required
    Playwright notices.

## References

- [Claude Code plugin reference](https://code.claude.com/docs/en/plugins-reference)
- [Claude Code plugin creation](https://code.claude.com/docs/en/plugins)
- [OpenAI plugin architecture](https://developers.openai.com/plugins/concepts/plugins)
- [OpenAI plugin packaging](https://developers.openai.com/plugins/build/plugins)
- [Playwright MCP Chrome extension setup](https://github.com/microsoft/playwright/blob/main/packages/extension/README.md)
- Existing local benchmark and fork design notes in
  `~/Documents/GitHub/playwright/.local-dev/`
