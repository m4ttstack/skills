# mattstack

The mattstack skill collection for Claude Code: browser, orchestration,
infra, and workflow skills, built for Matt Goodwin's own day-to-day use and
shared here as a public reference. Most skills are scoped under the
`mattstack:` prefix.

## Fast Browser

[**Fast Browser**](https://github.com/m4ttstack/fast-browser) lets Claude Code and Codex drive the
Chrome you already have open, with your profile and logins, instead of a blank
automated browser. Published as
[`@mattstack/fast-browser`](https://www.npmjs.com/package/@mattstack/fast-browser):

```bash
npx @mattstack/fast-browser setup --host both
```

It is MIT licensed; the Playwright-derived runtime and extension artifacts it
installs remain Apache-2.0.

See the [Fast Browser README](https://github.com/m4ttstack/fast-browser#readme)
for requirements, safe and full profiles, unpublished local builds, Chrome
developer-mode loading, diagnostics, migration, rollback, uninstall, privacy,
and security guidance.

Fast Browser's canonical public repo is
[github.com/m4ttstack/fast-browser](https://github.com/m4ttstack/fast-browser),
published from a filtered copy of this repo's history. It no longer lives in
this repo: the `plugins/fast-browser` copy kept here during the split has been
removed now that the setup above runs from the standalone package.

## Skills

### orchestration

- **mattstack:shepherdr** -- shepherd a herd of Claude Code agents via herdr panes. Breaks work into jobs, spawns an agent per job, monitors progress, sends follow-ups, and reports status. Requires the [herdr skill](https://github.com/ogulcancelik/herdr/blob/master/SKILL.md) (auto-installed if missing).
- **mattstack:remote-agent** -- launch a Claude Code agent in a fresh herdr pane under a chosen account and model, in a target repo, with `/remote-control` enabled so it can be continued from your phone or claude.ai/code.
- **model-tiering** -- pick the least capable model that can succeed at each unit of work, for both spawn-time (shepherd picking worker models) and delegation-time (a worker dispatching sub-agents) decisions.

### infra

- **mattstack:local-app** -- set up a local web app as a persistent macOS service with HTTPS via portless and launchd. Handles port selection, plist creation, portless routing, and health checks.
- **mattstack:remote-brainstorm** -- expose the superpowers visual brainstorming companion publicly through the shared portless/Cloudflare tunnel pipeline, so a visual brainstorm can be joined away from the machine running it.
- **mattstack:run-feedback** -- analyze a run against the training plan with per-mile split breakdown, effort classification, and trend context. Generates data-dense feedback stored in the training app.
- **mattstack:getting-current-time** -- read the machine clock whenever the current time matters. A shell script prints local time, IANA zone name, UTC offset, and UTC time in one shot instead of estimating from context.

### workflow

- **mattstack:matts-writing-style** -- voice, concision, and formatting rules for MR descriptions, MR comments, commit messages, and technical writing posted under Matt's name.

### ui

- **mattstack:building-with-alpine-halfmoon** -- build or restyle a no-build-step web UI on Alpine.js, Halfmoon CSS, and Radix Colors; covers where the Modern/Elegant core styles silently fail to apply.

### browser

These ship inside [Fast Browser](https://github.com/m4ttstack/fast-browser) and
are listed here for discoverability:

- **fast-browsing** -- drive a browser through Fast Browser's tools at near-human speed: macro check first, scout once, batch whole flows into one script, read targeted.
- **browser-macros** -- library of pre-written flow scripts run via `browser_run_code_unsafe` (filename + args). Index in `MACROS.md`.
- **mine-macros** -- sweep session logs for repeated browser flows, propose parameterized macros with evidence, and update the library after per-macro approval.
- **annotating-screenshots** -- mark up a browser screenshot before it's shown or shared: highlight a changed value, point at a control, label a step, or blur out PII.
- **capturing-flows** -- record a browser session and deliver it as a GIF when motion is the evidence: a multi-step flow, a transition, a loading state, a bug that only shows while it happens.

## Legacy skill-only setup

The symlinks below are the pre-plugin setup. Existing browser-skill users can
review and migrate that state with `npx @mattstack/fast-browser migrate
--dry-run` followed by `npx @mattstack/fast-browser migrate --host both`; new
Fast Browser installs should use the setup above.

Symlink each skill directory into `~/.claude/skills/`:

```bash
ln -s ~/Documents/GitHub/mattstack/skills/orchestration/shepherdr ~/.claude/skills/mattstack:shepherdr
ln -s ~/Documents/GitHub/mattstack/skills/orchestration/remote-agent ~/.claude/skills/mattstack:remote-agent
ln -s ~/Documents/GitHub/mattstack/skills/orchestration/model-tiering ~/.claude/skills/model-tiering
ln -s ~/Documents/GitHub/mattstack/skills/workflow/matts-writing-style ~/.claude/skills/mattstack:matts-writing-style
ln -s ~/Documents/GitHub/mattstack/skills/infra/local-app ~/.claude/skills/mattstack:local-app
ln -s ~/Documents/GitHub/mattstack/skills/infra/remote-brainstorm ~/.claude/skills/mattstack:remote-brainstorm
ln -s ~/Documents/GitHub/mattstack/skills/infra/run-feedback ~/.claude/skills/mattstack:run-feedback
ln -s ~/Documents/GitHub/mattstack/skills/infra/getting-current-time ~/.claude/skills/mattstack:getting-current-time
ln -s ~/Documents/GitHub/mattstack/skills/ui/building-with-alpine-halfmoon ~/.claude/skills/mattstack:building-with-alpine-halfmoon
```
