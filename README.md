# mattstack

The mattstack skill collection for Claude Code: orchestration and infra skills,
built for Matt Goodwin's own day-to-day use and shared here as a public
reference. Every skill is scoped under the `mattstack:` prefix. The browser
skills are catalogued here too, but they ship inside Fast Browser rather than
from this repo.

Skills wired to Matt's own machine, domains, and data live separately at
[m4ttheweric/skills](https://github.com/m4ttheweric/skills) under the `matt:`
prefix. What stays here is what someone else could actually pick up.

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

Fast Browser is its own repo and its own package. It started life inside this
one, so its history is a filtered copy of this repo's, but nothing about it
lives here now.

## Skills

### orchestration

- **mattstack:shepherdr** -- shepherd a herd of Claude Code agents via herdr panes. Breaks work into jobs, spawns an agent per job, monitors progress, sends follow-ups, and reports status. Requires the [herdr skill](https://github.com/ogulcancelik/herdr/blob/master/SKILL.md) (auto-installed if missing).
- **mattstack:model-tiering** -- pick the least capable model that can succeed at each unit of work, for both spawn-time (shepherd picking worker models) and delegation-time (a worker dispatching sub-agents) decisions.

### infra

- **mattstack:getting-current-time** -- read the machine clock whenever the current time matters. A shell script prints local time, IANA zone name, UTC offset, and UTC time in one shot instead of estimating from context.

### browser

Catalogued here so they are findable, but they install with
[Fast Browser](https://github.com/m4ttstack/fast-browser), not from this repo:

- **fast-browsing** -- drive a browser through Fast Browser's tools at near-human speed: macro check first, scout once, batch whole flows into one script, read targeted.
- **browser-macros** -- library of pre-written flow scripts run via `browser_run_code_unsafe` (filename + args). Index in `MACROS.md`.
- **mine-macros** -- sweep session logs for repeated browser flows, propose parameterized macros with evidence, and update the library after per-macro approval.
- **annotating-screenshots** -- mark up a browser screenshot before it's shown or shared: highlight a changed value, point at a control, label a step, or blur out PII.
- **capturing-flows** -- record a browser session and deliver it as a GIF when motion is the evidence: a multi-step flow, a transition, a loading state, a bug that only shows while it happens.

## Install

Symlink each skill directory into `~/.claude/skills/`, named with its prefix:

```bash
ln -s ~/Documents/GitHub/mattstack/skills/orchestration/shepherdr ~/.claude/skills/mattstack:shepherdr
ln -s ~/Documents/GitHub/mattstack/skills/orchestration/model-tiering ~/.claude/skills/mattstack:model-tiering
ln -s ~/Documents/GitHub/mattstack/skills/infra/getting-current-time ~/.claude/skills/mattstack:getting-current-time
```

The prefix is asserted in two places per skill: the symlink name above and the
`name:` field in that skill's `SKILL.md` frontmatter. They have to agree.

Anyone still on the old symlink-only browser setup can review and migrate that
state with `npx @mattstack/fast-browser migrate --dry-run` followed by `npx
@mattstack/fast-browser migrate --host both`.
