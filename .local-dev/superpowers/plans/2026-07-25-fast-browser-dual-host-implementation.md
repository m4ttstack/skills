# Fast Browser Dual-Host Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a distributable macOS-and-Chrome Fast Browser product with one plugin directory that provides full browser-workflow parity in Claude Code and Codex.

**Architecture:** The implementation is split into three independently reviewable plans. The Playwright fork produces a versioned MCP runtime and Chrome extension; `mattstack` provides the dual-host plugin and setup CLI; the final plan binds them together with migration, real-host E2E, performance checks, and release gates.

**Tech Stack:** Node.js 20+ ESM, built-in `node:test`, Playwright's TypeScript test harness, Chrome Manifest V3, MCP over stdio, macOS Keychain via `/usr/bin/security`, Claude Code and Codex plugin marketplaces.

## Global Constraints

- Initial platform is macOS + Google Chrome only.
- The same physical plugin directory must contain both `.claude-plugin/plugin.json` and `.codex-plugin/plugin.json`.
- Public setup defaults to the `safe` profile; Matt's migrated setup uses the explicit `full` profile.
- Normal actions use `snapshot-mode=none` and a 200 ms settle timeout.
- Multiple Claude Code and Codex clients must remain connected simultaneously without stealing focus.
- No token, personal path, session log, or personal macro may ship in an artifact.
- Pairing secrets live only in macOS Keychain and the extension's local storage.
- Session recording and macro-mining inputs are off in `safe` and on in `full`.
- Mined macros require explicit per-macro approval before installation.
- Setup, update, migration, rollback, and uninstall must preserve unrelated user state and be idempotent.
- Runtime startup performs no dependency installation and no artifact download.
- The implementation must retain applicable Playwright Apache-2.0 notices.
- The existing uncommitted changes in `skills/infra/local-app/SKILL.md` and `skills/workflow/matts-writing-style/SKILL.md` are user-owned and must remain untouched.

---

## Plan Set and Dependency Order

### Plan 1: Playwright runtime and Chrome extension

File:
`.local-dev/superpowers/plans/2026-07-25-fast-browser-runtime-extension.md`

Repository: `m4ttheweric/playwright`

Deliverable: checksum-addressed runtime and extension artifacts built from the
fork, with an independent extension identity and regression coverage for the
speed, macro, concurrency, and focus behavior.

This plan must finish first because Plan 2's `runtime-lock.json` consumes its
release-manifest schema.

### Plan 2: Dual-host plugin and setup CLI

File:
`.local-dev/superpowers/plans/2026-07-25-fast-browser-plugin-cli.md`

Repository: `m4ttheweric/mattstack`

Deliverable: one dual-host plugin directory, shared browser skills, runtime
wrapper, Keychain integration, host adapters, transactional migration, doctor,
configure, and uninstall commands.

This plan may use locally built Plan 1 artifacts. It must finish before any live
home-directory migration.

### Plan 3: Parity E2E, migration, and release

File:
`.local-dev/superpowers/plans/2026-07-25-fast-browser-parity-migration-release.md`

Repositories: `m4ttheweric/mattstack` and the artifact output from
`m4ttheweric/playwright`

Deliverable: deterministic direct-MCP tests, real Claude Code and Codex host
tests, two-client focus checks, Matt's reversible migration, package validation,
and a release-readiness report.

## Subagent-Driven Execution Rules

The user selected subagent-driven execution.

1. Create isolated worktrees before implementation:
   - a `fast-browser-runtime` branch from the current
     `multi-connection-extension` HEAD in the Playwright repository;
   - a `fast-browser-dual-host` branch from the commit containing this plan set
     in the mattstack repository.
2. Execute one numbered task at a time with a fresh implementation subagent.
3. After each task, run the subagent-driven skill's spec-compliance review and
   code-quality review before continuing.
4. Give every subagent the exact worktree, plan file, task number, and global
   constraints; do not ask a subagent to reread the entire conversation.
5. Do not let two subagents edit the same worktree concurrently.
6. Commit after every accepted task using the commit message specified in that
   task.
7. Keep the user's original mattstack worktree and its unrelated dirty files
   unchanged.
8. Run the verification-before-completion skill after all three plans pass.

## Completion Gate

Work is complete only when:

- all three plan files have every task checked;
- the Playwright and mattstack branches are clean;
- all unit, integration, plugin-validation, extension, and E2E checks pass;
- Matt's full-profile Claude Code and Codex installations pass `doctor`;
- simultaneous host connections preserve focus and isolation;
- the migration rollback has been exercised;
- packaged artifacts contain no forbidden paths or secrets; and
- the only remaining publication actions, if any, require external account
  credentials such as npm or Chrome Web Store publisher access and are
  explicitly listed.
