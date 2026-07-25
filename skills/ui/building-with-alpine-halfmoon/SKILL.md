---
name: mattstack:building-with-alpine-halfmoon
description: "Use when building or restyling a web UI with no build step (a dashboard, board, or internal tool served by its own server), when the stack is any of Alpine.js, Halfmoon CSS, or Radix Colors, or when Halfmoon styles or its Modern/Elegant core mysteriously fail to apply."
---

# Building with Alpine + Halfmoon + Radix Colors

Three vendored files, zero build step, zero npm dependencies. Alpine.js owns
reactivity. Halfmoon 2.x owns components. Radix Colors owns every color.

**Core principle: feed the frameworks, never fight them.** Halfmoon is a
CSS-only Bootstrap 5.3 drop-in that is fully CSS-variable driven; you theme it
by overriding its `--bs-*` hooks, never by re-authoring component rules or
minting your own theme attribute. Hand-picked colors are banned; every shade
is a named step from a published Radix scale.

**Reference implementation:** `~/Documents/GitHub/local-apps`, files
`src/board.html` (shell + the full worked Radix palette block),
`src/board.js` (Alpine component), `src/board-assets.ts` and its test
(vendored-asset serving). It is live and verified; copy from it rather than
deriving from scratch.

## Halfmoon 2.x reality check

Most agents carry a Halfmoon 1.x model. All of these are wrong in 2.x:

| Wrong (Halfmoon 1 era) | Right (Halfmoon 2.x) |
| --- | --- |
| `badge-success`, `badge-danger` | `badge text-bg-success`, `badge text-bg-danger` |
| hand-rolled `.switch .slider` toggle | `form-check form-switch` + `<input type="checkbox" role="switch">` |
| `.page-wrapper`, `.content` layout | plain Bootstrap `container`, grid, utilities |
| "Halfmoon ships its own JS" | CSS-only; there is no Halfmoon JS. Alpine drives everything |
| own dark-mode class or attribute | `data-bs-theme="light|dark"` on `<html>`, built in |
| one `halfmoon.modern.min.css` file | `halfmoon.min.css` PLUS a separate core file `cores/halfmoon.modern.css` |

It is a Bootstrap 5.3 drop-in with identical class names: `card`,
`table table-hover`, `badge`, `alert alert-*`, `btn btn-sm btn-outline-*`,
`spinner-border spinner-border-sm`, `form-control`, `font-monospace`,
`text-body-secondary`. Write stock Bootstrap 5.3 markup and it styles itself.

## Vendoring and serving

- Vendor exactly: `halfmoon.min.css`, one core (e.g. `halfmoon.modern.css`),
  `alpine.min.js` (the jsdelivr CDN build). Pin versions; commit the files. A
  fresh checkout must serve the UI with no network and no install step.
- First line of each vendored file is a provenance header:
  `/*! alpinejs 3.15.12 https://cdn.jsdelivr.net/npm/alpinejs@3.15.12/dist/cdn.min.js vendored 2026-07-25 */`
- Serve through an exact-name allowlist (a literal map of the vendored
  filenames), never filesystem resolution. Guard lookups with
  `Object.hasOwn(VENDOR, name)`: a plain `VENDOR[name]` resolves
  `constructor`, `toString`, and `__proto__` off the prototype chain and
  crashes. Test that `/vendor/constructor` and traversal paths 404.
- `cache-control: no-cache` on everything; there is no cache-busting scheme
  because there is no build.

## The HTML shell: three load-bearing details

1. `<html lang="en" data-bs-theme="light" data-bs-core="modern">`. Every
   rule in a Halfmoon core file is gated on `[data-bs-core=...]`. Without
   the attribute the core loads but is silently inert: nothing errors, the
   page just renders on the default core. This shipped to production once.
2. Script order: your component file BEFORE `alpine.min.js`, both `defer`.
   The CDN build dispatches `alpine:init` the instant it executes, so your
   `Alpine.data('board', ...)` registration must already be listening:
   ```html
   <script src="/board.js" defer></script>
   <script src="/vendor/alpine.min.js" defer></script>
   ```
3. `[x-cloak] { display: none !important; }` in CSS plus `x-cloak` on the
   root element. Accepted tradeoff: blank page if Alpine ever fails to
   load, instead of a flash of raw template.

Dark mode is two lines in `init()`, not a theming system: set
`data-bs-theme` on `<html>` from
`matchMedia("(prefers-color-scheme: dark)")` and subscribe to its `change`
event.

## Alpine rules

- The component file is state and actions only. Zero HTML strings. `x-text`
  everywhere (it escapes by default); never `x-html`. Add a test that greps
  the client file for the forbidden sink.
- `<template x-for>` keyed (`:key="row.name"`). Keyed rows morph in place,
  which is what lets a focused input survive a poll refresh; keep an
  `editing` guard on the refresh anyway.
- `<template x-if>` needs exactly one root element inside.
- Modal: stock Bootstrap modal markup (`modal-dialog/-content/-header/
  -body/-footer`) driven purely by Alpine. Wrap in
  `<template x-if="pwModal">`, show with `.modal.d-block` plus a sibling
  `.modal-backdrop.show` div, focus via `x-init="$el.focus()"`, close on
  `@keydown.escape.window` and backdrop click, submit on `@keydown.enter`.
  Do not invent a custom overlay wrapper; the Bootstrap classes are already
  themed.

## Radix palette onto Halfmoon's hooks

Do NOT vendor Radix CSS files or re-style components by hand. Radix values
go into Halfmoon's own variables, so every component (including ones you
never touch: spinners, alerts, focus rings, disabled states) follows.

1. Fetch exact values from
   `https://cdn.jsdelivr.net/npm/@radix-ui/colors@3.0.0/<scale>.css` and
   `<scale>-dark.css` at authoring time. Never write Radix values from
   memory.
2. Pick families once: `slate` all neutrals, one accent (`indigo`),
   `grass` success, `amber` warning, `red` danger.
3. Radix step conventions: 9 solid (dots, switch fill, solid buttons; step
   9 is the same hex in light and dark, so solids need no dark re-pin);
   3 bg + 11 text for soft badges; 11 links and emphasis; 6 to 8 borders;
   dark theme page = dark step 1, panels (cards, modals) = dark step 2 via
   `--bs-content-bg-hsl`.
4. Halfmoon consumes HSL triplet variables shaped `131.1, 40.9%, 46.5%`
   (no `hsl()` wrapper). Pin the `-hsl` forms; plain forms defined as
   `hsl(var(--...-hsl))` update automatically. But ONLY tokens the vendor
   actually defines with an `-hsl` suffix take triplets; do not invent
   `-hsl` names. Tokens the vendor defines as plain colors (`-bg-subtle`,
   `-border-subtle`, `-hover-bg`, `-active-bg`, `--bs-border-color`) are
   pinned as plain hex. When unsure, grep the vendored css for the token
   name. Also override the `-hue`/`-saturation` anchors so every derived
   tint recomputes inside the Radix family.
5. Specificity, learned the hard way:
   - Core files define tokens at (0,2,0), e.g.
     `[data-bs-core=modern]:not([data-bs-theme=dark])`. Pin light tokens in
     `:root[data-bs-core="modern"]`, dark tokens in
     `:root[data-bs-theme="dark"]`, and put the dark block LAST.
   - Every token you pin globally that the vendor flips in dark (all
     `-text-emphasis`, `-bg-subtle`, `-border-subtle`, and the neutral
     text/bg/border tokens) MUST be re-pinned in your dark block, or dark
     mode renders your light values.
   - The Modern core remaps `--bs-primary-*` straight to its own hue
     families (navy light, sky dark), bypassing `--bs-blue-*`. Override
     `--bs-primary-*` directly, including `-hover-bg`, `-active-bg`,
     `-text-emphasis`, `-foreground`.
6. Soft badges ride the family tokens so they flip with the theme (the
   vendor's background rule carries `!important`, so yours must too):
   ```css
   .badge.text-bg-success {
     --bs-color-hsl: var(--bs-green-text-emphasis-hsl);
     background-color: var(--bs-green-bg-subtle) !important;
   }
   ```
7. Outline buttons through Bootstrap's own vars: step 11 text, step 7-8
   border, step 3 wash on hover. Set `--bs-btn-color`,
   `--bs-btn-border-color`, and the three `--bs-btn-hover-*` per theme.

The complete worked block (about 100 lines, light + dark, each value
commented with its Radix step) lives in the reference `src/board.html`.
Start from it and swap scales.

## Verify with your own eyes, in a way you can actually run

Never declare UI done from code reading or a subagent's claim. Manual
devtools instructions ("toggle OS appearance") are not executable by an
agent; this loop is:

- `playwright-core` (installed in the scratchpad, never the repo) launched
  against the local
  `chromium_headless_shell-*/chrome-headless-shell-mac-arm64/chrome-headless-shell`
  under `~/Library/Caches/ms-playwright`. Deterministic; browser MCP relays
  can die mid-session.
- Shoot light AND dark (`colorScheme` context option) plus every
  interactive state: modal open with focus, an edit mid-flight, a toggle
  round-trip, spinners.
- Collect `pageerror` events; require zero across the run.
- Read the screenshots yourself. Fix, re-shoot, and only then show a human.
