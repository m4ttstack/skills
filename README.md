# mattstack

Personal Claude Code skills for Matt Goodwin. All skills are scoped under the `mattstack:` prefix.

## Fast Browser plugin candidate

The repository now contains a dual-host Fast Browser alpha for Claude Code and
Codex under `plugins/fast-browser`. The npm package is still private and
UNLICENSED, so it is not available through `npx` yet. Current installs must use
the repository source:

```bash
node plugins/fast-browser/bin/fast-browser.mjs setup \
  --source /path/to/mattstack \
  --host both
```

See the [Fast Browser README](plugins/fast-browser/README.md) for requirements,
safe and full profiles, Chrome developer-mode loading, diagnostics, migration,
rollback, uninstall, privacy, and security guidance.

## Skills

### orchestration

- **mattstack:shepherdr** -- shepherd a herd of Claude Code agents via herdr panes. Breaks work into jobs, spawns an agent per job, monitors progress, sends follow-ups, and reports status. Requires the [herdr skill](https://github.com/ogulcancelik/herdr/blob/master/SKILL.md) (auto-installed if missing).

### infra

- **mattstack:local-app** -- set up a local web app as a persistent macOS service with HTTPS via portless and launchd. Handles port selection, plist creation, portless routing, and health checks.
- **mattstack:run-feedback** -- analyze a run against the training plan with per-mile split breakdown, effort classification, and trend context. Generates data-dense feedback stored in the training app.
- **mattstack:getting-current-time** -- read the machine clock whenever the current time matters. A shell script prints local time, IANA zone name, UTC offset, and UTC time in one shot instead of estimating from context.

### workflow

- **mattstack:matts-writing-style** -- voice, concision, and formatting rules for MR descriptions, MR comments, commit messages, and technical writing posted under Matt's name.

### browser

- **mattstack:fast-browsing** -- drive a browser through Playwright MCP tools at near-human speed: macro check first, scout once, batch whole flows into one script, read targeted.
- **mattstack:browser-macros** -- library of pre-written Playwright flow scripts (run via `browser_run_code_unsafe` filename+args). Index in `MACROS.md`; scripts live in `~/.playwright-mcp/macros/` (the MCP server only reads files under its output dir or cwd).
- **mattstack:mine-macros** -- sweep `~/.playwright-mcp` session logs for repeated browser flows, propose parameterized macros with evidence, and update the library after per-macro approval.

## Legacy skill-only setup

The symlinks below are the pre-plugin setup. Existing browser-skill users can
review and migrate that state with
`node plugins/fast-browser/bin/fast-browser.mjs migrate --dry-run` followed by
`node plugins/fast-browser/bin/fast-browser.mjs migrate --host both`; new Fast
Browser installs should use the plugin candidate workflow above.

Symlink each skill directory into `~/.claude/skills/`:

```bash
ln -s ~/Documents/GitHub/mattstack/skills/orchestration/shepherdr ~/.claude/skills/mattstack:shepherdr
ln -s ~/Documents/GitHub/mattstack/skills/workflow/matts-writing-style ~/.claude/skills/mattstack:matts-writing-style
ln -s ~/Documents/GitHub/mattstack/skills/infra/local-app ~/.claude/skills/mattstack:local-app
ln -s ~/Documents/GitHub/mattstack/skills/infra/run-feedback ~/.claude/skills/mattstack:run-feedback
ln -s ~/Documents/GitHub/mattstack/skills/infra/getting-current-time ~/.claude/skills/mattstack:getting-current-time
ln -s ~/Documents/GitHub/mattstack/skills/browser/fast-browsing ~/.claude/skills/mattstack:fast-browsing
ln -s ~/Documents/GitHub/mattstack/skills/browser/browser-macros ~/.claude/skills/mattstack:browser-macros
ln -s ~/Documents/GitHub/mattstack/skills/browser/mine-macros ~/.claude/skills/mattstack:mine-macros
```
