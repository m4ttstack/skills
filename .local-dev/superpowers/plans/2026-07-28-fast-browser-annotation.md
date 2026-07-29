# Fast Browser Screenshot Annotation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let an agent annotate a Fast Browser screenshot with arrows, highlights, labels and redactions whose coordinates are measured from the live DOM rather than estimated from the image.

**Architecture:** One macro captures the PNG and measures selector bounding boxes in a single page state (atomicity is the integrity guarantee). A new `fast-browser annotate` CLI command builds an SVG over the base PNG using the eight primitives ported from `annotate.py`, pipes it to `rsvg-convert`, and writes a 2x raster. Palettes come from vendored Radix Colors scales.

**Tech Stack:** Node 20+ ESM, `node:test`, zero runtime dependencies, `rsvg-convert` (librsvg) as an external binary, Playwright via the pinned Fast Browser MCP runtime.

**Spec:** `.local-dev/superpowers/specs/2026-07-28-fast-browser-annotation-design.md`

## Global Constraints

- **Zero runtime dependencies.** `package.json` `dependencies` must stay `{}`. Radix values are vendored as data.
- **Node 20+**, ESM only (`.mjs`), no TypeScript.
- **No em dashes or en dashes** in any code, comment, doc or commit message. Use ellipses or rephrase.
- **Repo location:** all paths below are relative to `plugins/fast-browser/`.
- **Tests:** `node --test`, files as `tests/unit/*.test.mjs` or `tests/integration/*.test.mjs`. Run with `npm test`.
- **Error types:** reuse `LifecycleError` from `lib/commands/shared.mjs` (`(message, { stage, partialState, exitCode, code })`) and `UsageError` from `lib/cli/parse-args.mjs`. Do not introduce a new error class; `lib/cli/main.mjs` `safeFailure()` only passes through `LifecycleError`, `UsageError`, `PairingError`, `MigrationError`.
- **Path containment:** every filesystem write must go through `assertConfinedPath({ dataDir, rootDir, candidate })` from `lib/core/containment.mjs`.
- **Never write the intermediate SVG to disk.** It embeds the unredacted screenshot as base64.
- **Commit after each task** with a conventional-commit message.

---

### Task 1: Radix palette registry

**Files:**
- Create: `lib/annotate/palette.mjs`
- Test: `tests/unit/annotate-palette.test.mjs`

**Interfaces:**
- Consumes: nothing
- Produces: `RADIX_SCALES` (frozen object), `DEFAULT_PALETTE` (string `'violet'`), `OFFERED_PALETTES` (frozen array of 10 strings), `resolvePalette(name) -> { accent, soft, ink }` (throws `LifecycleError` on unknown name)

- [ ] **Step 1: Write the failing test**

```js
// tests/unit/annotate-palette.test.mjs
import assert from 'node:assert/strict';
import test from 'node:test';

import {
  DEFAULT_PALETTE,
  OFFERED_PALETTES,
  RADIX_SCALES,
  resolvePalette,
} from '../../lib/annotate/palette.mjs';

test('the default palette is violet and resolves to Radix step 9/3/11', () => {
  assert.equal(DEFAULT_PALETTE, 'violet');
  assert.deepEqual(resolvePalette('violet'), {
    accent: '#6e56cf',
    soft: '#f4f0fe',
    ink: '#6550b9',
  });
});

test('every Radix scale resolves, not only the offered ten', () => {
  assert.equal(Object.keys(RADIX_SCALES).length, 31);
  for (const name of Object.keys(RADIX_SCALES)) {
    const palette = resolvePalette(name);
    for (const role of ['accent', 'soft', 'ink']) {
      assert.match(palette[role], /^#[0-9a-f]{6}$/, `${name}.${role}`);
    }
  }
});

test('the offered ten are a subset of the full set and lead with the default', () => {
  assert.equal(OFFERED_PALETTES.length, 10);
  assert.equal(OFFERED_PALETTES[0], DEFAULT_PALETTE);
  for (const name of OFFERED_PALETTES) assert.ok(RADIX_SCALES[name], name);
});

test('an unknown palette name is refused rather than silently defaulted', () => {
  assert.throws(() => resolvePalette('burgundy'), /unknown annotation palette/);
  assert.throws(() => resolvePalette('__proto__'), /unknown annotation palette/);
});

test('the registry cannot be mutated by a caller', () => {
  assert.throws(() => { RADIX_SCALES.violet = null; });
  // Nested too: freezing only the outer object leaves every per-scale entry
  // writable, so a single stray assignment would corrupt the palette for the
  // life of the process and every later resolvePalette() would return it.
  assert.throws(() => { RADIX_SCALES.violet.accent = '#000000'; });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm run test:unit -- --test-name-pattern="palette"`
Expected: FAIL, cannot find module `lib/annotate/palette.mjs`

- [ ] **Step 3: Write minimal implementation**

```js
// lib/annotate/palette.mjs
import { LifecycleError } from '../commands/shared.mjs';

// Vendored from @radix-ui/colors v3 (MIT). Each entry is one Radix light
// scale reduced to the three steps the annotator needs:
//   accent = step 9  (solid)               strokes, borders, counter fill,
//                                          and highlight fill at 14% opacity
//   soft   = step 3  (subtle component bg) chip fill only
//   ink    = step 11 (accessible text)     chip label text
// Radix guarantees step 11 reads accessibly on step 3, which is why the trio
// is taken from one scale rather than hand-picked.
//
// Deep-frozen, not just Object.freeze on the outer table: this module is
// exported directly, and freezing only the top level would leave every
// per-scale object writable. One stray `RADIX_SCALES.violet.accent = ...`
// would then corrupt the palette for the life of the process.
const SCALES = {
  amber: { accent: '#ffc53d', soft: '#fff7c2', ink: '#ab6400' },
  blue: { accent: '#0090ff', soft: '#e6f4fe', ink: '#0d74ce' },
  bronze: { accent: '#a18072', soft: '#f6edea', ink: '#7d5e54' },
  brown: { accent: '#ad7f58', soft: '#f6eee7', ink: '#815e46' },
  crimson: { accent: '#e93d82', soft: '#ffe9f0', ink: '#cb1d63' },
  cyan: { accent: '#00a2c7', soft: '#def7f9', ink: '#107d98' },
  gold: { accent: '#978365', soft: '#f2f0e7', ink: '#71624b' },
  grass: { accent: '#46a758', soft: '#e9f6e9', ink: '#2a7e3b' },
  gray: { accent: '#8d8d8d', soft: '#f0f0f0', ink: '#646464' },
  green: { accent: '#30a46c', soft: '#e6f6eb', ink: '#218358' },
  indigo: { accent: '#3e63dd', soft: '#edf2fe', ink: '#3a5bc7' },
  iris: { accent: '#5b5bd6', soft: '#f0f1fe', ink: '#5753c6' },
  jade: { accent: '#29a383', soft: '#e6f7ed', ink: '#208368' },
  lime: { accent: '#bdee63', soft: '#eef6d6', ink: '#5c7c2f' },
  mauve: { accent: '#8e8c99', soft: '#f2eff3', ink: '#65636d' },
  mint: { accent: '#86ead4', soft: '#ddf9f2', ink: '#027864' },
  olive: { accent: '#898e87', soft: '#eff1ef', ink: '#60655f' },
  orange: { accent: '#f76b15', soft: '#ffefd6', ink: '#cc4e00' },
  pink: { accent: '#d6409f', soft: '#fee9f5', ink: '#c2298a' },
  plum: { accent: '#ab4aba', soft: '#fbebfb', ink: '#953ea3' },
  purple: { accent: '#8e4ec6', soft: '#f7edfe', ink: '#8145b5' },
  red: { accent: '#e5484d', soft: '#feebec', ink: '#ce2c31' },
  ruby: { accent: '#e54666', soft: '#feeaed', ink: '#ca244d' },
  sage: { accent: '#868e8b', soft: '#eef1f0', ink: '#5f6563' },
  sand: { accent: '#8d8d86', soft: '#f1f0ef', ink: '#63635e' },
  sky: { accent: '#7ce2fe', soft: '#e1f6fd', ink: '#00749e' },
  slate: { accent: '#8b8d98', soft: '#f0f0f3', ink: '#60646c' },
  teal: { accent: '#12a594', soft: '#e0f8f3', ink: '#008573' },
  tomato: { accent: '#e54d2e', soft: '#feebe7', ink: '#d13415' },
  violet: { accent: '#6e56cf', soft: '#f4f0fe', ink: '#6550b9' },
  yellow: { accent: '#ffe629', soft: '#fffab8', ink: '#9e6c00' },
};

export const RADIX_SCALES = Object.freeze(
  Object.fromEntries(
    Object.entries(SCALES).map(([name, scale]) => [name, Object.freeze(scale)]),
  ),
);

// Closest Radix scale to the #7C4DFF the source annotator hardcoded.
export const DEFAULT_PALETTE = 'violet';

// What the skill presents on first use. Config accepts any RADIX_SCALES key.
export const OFFERED_PALETTES = Object.freeze([
  'violet', 'iris', 'indigo',
  'crimson', 'red', 'orange',
  'teal', 'cyan', 'grass',
  'slate',
]);

export function resolvePalette(name) {
  // Own-property check: a bare `RADIX_SCALES[name]` would resolve
  // '__proto__' and 'constructor' to objects that are not palettes.
  if (typeof name !== 'string' || !Object.hasOwn(RADIX_SCALES, name)) {
    throw new LifecycleError(
      `unknown annotation palette: ${typeof name === 'string' ? name : '<invalid>'}`,
      { stage: 'validate', exitCode: 2 },
    );
  }
  return { ...RADIX_SCALES[name] };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm run test:unit -- --test-name-pattern="palette"`
Expected: PASS, 5 tests

- [ ] **Step 5: Add the Radix attribution to third-party notices**

Append to `THIRD_PARTY_NOTICES.md`:

```markdown
## Radix Colors

Colour scale values in `lib/annotate/palette.mjs` are derived from
[@radix-ui/colors](https://github.com/radix-ui/colors) v3, used under the MIT
License.

Copyright (c) 2022 WorkOS

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

- [ ] **Step 6: Commit**

```bash
git add lib/annotate/palette.mjs tests/unit/annotate-palette.test.mjs THIRD_PARTY_NOTICES.md
git commit -m "feat(fast-browser): add Radix annotation palette registry"
```

---

### Task 2: PNG header reader

**Files:**
- Create: `lib/annotate/png.mjs`
- Test: `tests/unit/annotate-png.test.mjs`

**Interfaces:**
- Consumes: nothing
- Produces: `readPngSize(buffer) -> { width, height }` (throws `LifecycleError` if not a PNG or truncated)

- [ ] **Step 1: Write the failing test**

```js
// tests/unit/annotate-png.test.mjs
import assert from 'node:assert/strict';
import test from 'node:test';

import { readPngSize } from '../../lib/annotate/png.mjs';

function pngHeader(width, height) {
  const buffer = Buffer.alloc(24);
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]).copy(buffer, 0);
  buffer.write('IHDR', 12, 'latin1');
  buffer.writeUInt32BE(width, 16);
  buffer.writeUInt32BE(height, 20);
  return buffer;
}

test('reads dimensions from a PNG IHDR header', () => {
  assert.deepEqual(readPngSize(pngHeader(900, 560)), { width: 900, height: 560 });
});

test('rejects a file that is not a PNG', () => {
  assert.throws(() => readPngSize(Buffer.from('GIF89a not a png at all!!')), /not a PNG/);
});

test('rejects a PNG whose header is truncated', () => {
  assert.throws(() => readPngSize(pngHeader(900, 560).subarray(0, 20)), /not a PNG/);
});

test('rejects a zero dimension', () => {
  assert.throws(() => readPngSize(pngHeader(0, 560)), /invalid PNG dimensions/);
  assert.throws(() => readPngSize(pngHeader(900, 0)), /invalid PNG dimensions/);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm run test:unit -- --test-name-pattern="PNG"`
Expected: FAIL, cannot find module `lib/annotate/png.mjs`

- [ ] **Step 3: Write minimal implementation**

```js
// lib/annotate/png.mjs
import { LifecycleError } from '../commands/shared.mjs';

const SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

// Dimensions come from the IHDR chunk, which a valid PNG is required to place
// first. Reading 24 bytes avoids decoding the image just to learn its size.
export function readPngSize(buffer) {
  if (
    !Buffer.isBuffer(buffer)
    || buffer.length < 24
    || !buffer.subarray(0, 8).equals(SIGNATURE)
    || buffer.subarray(12, 16).toString('latin1') !== 'IHDR'
  ) {
    throw new LifecycleError('the annotation base is not a PNG', {
      stage: 'validate',
      exitCode: 2,
    });
  }
  const width = buffer.readUInt32BE(16);
  const height = buffer.readUInt32BE(20);
  if (width < 1 || height < 1) {
    throw new LifecycleError('invalid PNG dimensions', { stage: 'validate', exitCode: 2 });
  }
  return { width, height };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm run test:unit -- --test-name-pattern="PNG"`
Expected: PASS, 4 tests

- [ ] **Step 5: Commit**

```bash
git add lib/annotate/png.mjs tests/unit/annotate-png.test.mjs
git commit -m "feat(fast-browser): read PNG dimensions from IHDR"
```

---

### Task 3: SVG builder with the eight primitives

**Files:**
- Create: `lib/annotate/svg.mjs`
- Test: `tests/unit/annotate-svg.test.mjs`

**Interfaces:**
- Consumes: `resolvePalette` (Task 1)
- Produces: `ANNOTATION_TYPES` (frozen array of 8 strings), `buildSvg({ base, width, height, annotations, palette, scale }) -> string` where `base` is a `Buffer` of the PNG; throws `LifecycleError` on any invalid annotation

**Note on divergence from `annotate.py`:** this port validates every field. The source interpolates `counter.n` into markup unescaped and trusts all types. Do not port that trust.

- [ ] **Step 1: Write the failing test**

```js
// tests/unit/annotate-svg.test.mjs
import assert from 'node:assert/strict';
import test from 'node:test';

import { ANNOTATION_TYPES, buildSvg } from '../../lib/annotate/svg.mjs';

const BASE = Buffer.alloc(24);
Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]).copy(BASE, 0);

function svg(annotations) {
  return buildSvg({
    base: BASE, width: 900, height: 560, annotations, palette: 'violet', scale: 2,
  });
}

test('all eight primitives are supported', () => {
  assert.deepEqual([...ANNOTATION_TYPES].sort(), [
    'arrow', 'blur', 'box', 'chip', 'counter', 'ellipse', 'highlight', 'spotlight',
  ]);
});

test('the root svg rasterises at scale while keeping base-pixel coordinates', () => {
  const out = svg([{ type: 'box', box: [10, 20, 30, 40] }]);
  assert.match(out, /width="1800" height="1120"/);
  assert.match(out, /viewBox="0 0 900 560"/);
});

test('highlight fills with accent at 14 percent, never with soft', () => {
  const out = svg([{ type: 'highlight', box: [10, 20, 30, 40] }]);
  assert.match(out, /fill="#6e56cf" fill-opacity="0\.14"/);
  assert.doesNotMatch(out, /fill="#f4f0fe" fill-opacity/);
});

test('chip uses soft fill with ink text', () => {
  const out = svg([{ type: 'chip', xy: [10, 20], text: 'Estimate' }]);
  assert.match(out, /fill="#f4f0fe"/);
  assert.match(out, /fill="#6550b9"/);
});

test('chip text is escaped so markup cannot be injected', () => {
  const out = svg([{ type: 'chip', xy: [0, 0], text: '<script>&"x"' }]);
  assert.doesNotMatch(out, /<script>/);
  assert.match(out, /&lt;script&gt;&amp;/);
});

test('counter n is validated as an integer rather than interpolated raw', () => {
  assert.throws(() => svg([{ type: 'counter', xy: [0, 0], n: '</text><script/>' }]), /counter/);
  assert.match(svg([{ type: 'counter', xy: [5, 5], n: 3 }]), />3</);
});

test('every generated element id is unique within one document', () => {
  const out = svg([
    { type: 'blur', box: [0, 0, 10, 10] },
    { type: 'spotlight', box: [0, 0, 10, 10] },
    { type: 'blur', box: [0, 0, 10, 10] },
  ]);
  const ids = [...out.matchAll(/id="(clip|blur|spot)(\d+)"/g)].map((m) => `${m[1]}${m[2]}`);
  assert.equal(new Set(ids).size, ids.length, 'every generated id is unique');
});

test('blur and spotlight advance one shared id counter', () => {
  const out = svg([
    { type: 'blur', box: [0, 0, 10, 10] },
    { type: 'spotlight', box: [0, 0, 10, 10] },
  ]);
  // A shared counter gives the spotlight index 2. Per-type counters would
  // restart it at 1, which a uniqueness check cannot see: the 'spot' prefix
  // keeps the strings distinct either way, so uniqueness alone proves nothing
  // about counter sharing.
  assert.match(out, /id="clip1"/);
  assert.match(out, /id="blur1"/);
  assert.match(out, /id="spot2"/);
  assert.doesNotMatch(out, /id="spot1"/);
});

test('an unknown annotation type is refused', () => {
  assert.throws(() => svg([{ type: 'sparkle', box: [0, 0, 1, 1] }]), /unsupported annotation/);
});

test('a non-finite or negative geometry value is refused', () => {
  assert.throws(() => svg([{ type: 'box', box: [0, 0, Number.NaN, 1] }]), /invalid/);
  assert.throws(() => svg([{ type: 'box', box: [0, 0, -5, 1] }]), /invalid/);
  assert.throws(() => svg([{ type: 'box', box: [0, 0, 1] }]), /invalid/);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm run test:unit -- --test-name-pattern="svg|primitive|chip|counter|highlight"`
Expected: FAIL, cannot find module `lib/annotate/svg.mjs`

- [ ] **Step 3: Write minimal implementation**

```js
// lib/annotate/svg.mjs
import { LifecycleError } from '../commands/shared.mjs';
import { resolvePalette } from './palette.mjs';

export const ANNOTATION_TYPES = Object.freeze([
  'arrow', 'chip', 'highlight', 'box', 'ellipse', 'counter', 'blur', 'spotlight',
]);

const ESCAPES = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' };

function esc(value) {
  return String(value).replace(/[&<>"']/g, (character) => ESCAPES[character]);
}

function invalid(field) {
  return new LifecycleError(`invalid annotation geometry: ${field}`, {
    stage: 'validate',
    exitCode: 2,
  });
}

function num(value, field, { min = -1e6, max = 1e6 } = {}) {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < min || value > max) {
    throw invalid(field);
  }
  return value;
}

function boxOf(annotation) {
  const box = annotation.box;
  if (!Array.isArray(box) || box.length !== 4) throw invalid('box');
  const [x, y] = [num(box[0], 'box.x'), num(box[1], 'box.y')];
  const w = num(box[2], 'box.width', { min: 0 });
  const h = num(box[3], 'box.height', { min: 0 });
  return { x, y, w, h };
}

function point(value, field) {
  if (!Array.isArray(value) || value.length !== 2) throw invalid(field);
  return [num(value[0], `${field}.x`), num(value[1], `${field}.y`)];
}

const DRAW = {
  arrow(a, ctx) {
    const [x1, y1] = point(a.tail, 'tail');
    const [x2, y2] = point(a.head, 'head');
    const bow = a.bow === undefined ? 0.18 : num(a.bow, 'bow', { min: -2, max: 2 });
    const width = a.width === undefined ? 5 : num(a.width, 'width', { min: 0.5, max: 40 });
    const dx = x2 - x1;
    const dy = y2 - y1;
    const cx = (x1 + x2) / 2 - dy * bow;
    const cy = (y1 + y2) / 2 + dx * bow;
    return `<path d="M ${x1} ${y1} Q ${cx} ${cy} ${x2} ${y2}" fill="none" `
      + `stroke="${ctx.accent}" stroke-width="${width}" stroke-linecap="round" `
      + 'marker-end="url(#head)" filter="url(#sh)"/>';
  },
  chip(a, ctx) {
    const [x, y] = point(a.xy, 'xy');
    if (typeof a.text !== 'string' || a.text.length === 0 || a.text.length > 200) {
      throw invalid('chip.text');
    }
    const size = a.size === undefined ? 22 : num(a.size, 'size', { min: 6, max: 96 });
    const padx = size * 0.7;
    const pady = size * 0.5;
    // [...a.text] counts code points, so astral characters (emoji) are not
    // double-counted the way a UTF-16 .length would count them.
    const w = a.w === undefined
      ? [...a.text].length * size * 0.58 + padx * 2
      : num(a.w, 'chip.w', { min: 1 });
    const h = size + pady * 2;
    return `<g filter="url(#sh)">`
      + `<rect x="${x}" y="${y}" width="${w.toFixed(0)}" height="${h.toFixed(0)}" `
      + `rx="${(h / 2.2).toFixed(0)}" fill="${ctx.soft}" stroke="${ctx.accent}" stroke-width="1.5"/>`
      + `<text x="${(x + w / 2).toFixed(0)}" y="${(y + h / 2).toFixed(0)}" fill="${ctx.ink}" `
      + 'font-family="-apple-system, Helvetica, Arial, sans-serif" '
      + `font-size="${size}" font-weight="700" text-anchor="middle" `
      + `dominant-baseline="central">${esc(a.text)}</text></g>`;
  },
  highlight(a, ctx) {
    const { x, y, w, h } = boxOf(a);
    // accent at low opacity, NOT soft: Radix step 3 is near-white and would be
    // invisible at 14% over a light UI.
    return `<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="6" `
      + `fill="${ctx.accent}" fill-opacity="0.14" stroke="${ctx.accent}" stroke-width="2.5"/>`;
  },
  box(a, ctx) {
    const { x, y, w, h } = boxOf(a);
    return `<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="6" fill="none" `
      + `stroke="${ctx.accent}" stroke-width="3" filter="url(#sh)"/>`;
  },
  ellipse(a, ctx) {
    const cx = num(a.cx, 'cx');
    const cy = num(a.cy, 'cy');
    const rx = num(a.rx, 'rx', { min: 0 });
    const ry = a.ry === undefined ? rx : num(a.ry, 'ry', { min: 0 });
    return `<ellipse cx="${cx}" cy="${cy}" rx="${rx}" ry="${ry}" fill="none" `
      + `stroke="${ctx.accent}" stroke-width="3" filter="url(#sh)"/>`;
  },
  counter(a, ctx) {
    const [x, y] = point(a.xy, 'xy');
    if (!Number.isInteger(a.n) || a.n < 0 || a.n > 999) throw invalid('counter.n');
    const size = a.size === undefined ? 18 : num(a.size, 'size', { min: 6, max: 96 });
    const r = size * 0.9;
    return `<g filter="url(#sh)"><circle cx="${x}" cy="${y}" r="${r.toFixed(0)}" `
      + `fill="${ctx.accent}"/>`
      + `<text x="${x}" y="${y}" fill="white" font-size="${size}" font-weight="700" `
      + 'font-family="-apple-system, Helvetica, Arial, sans-serif" '
      + `text-anchor="middle" dominant-baseline="central">${a.n}</text></g>`;
  },
  blur(a, ctx) {
    const { x, y, w, h } = boxOf(a);
    const amount = a.amount === undefined ? 8 : num(a.amount, 'amount', { min: 0.5, max: 100 });
    const i = ctx.nextId();
    return `<clipPath id="clip${i}"><rect x="${x}" y="${y}" width="${w}" height="${h}"/></clipPath>`
      + `<filter id="blur${i}" x="-20%" y="-20%" width="140%" height="140%">`
      + `<feGaussianBlur stdDeviation="${amount}"/></filter>`
      + `<g clip-path="url(#clip${i})"><image href="${ctx.uri}" x="0" y="0" `
      + `width="${ctx.width}" height="${ctx.height}" filter="url(#blur${i})"/></g>`;
  },
  spotlight(a, ctx) {
    const { x, y, w, h } = boxOf(a);
    const dim = a.dim === undefined ? 0.55 : num(a.dim, 'dim', { min: 0, max: 1 });
    const i = ctx.nextId();
    return `<mask id="spot${i}"><rect x="0" y="0" width="${ctx.width}" height="${ctx.height}" `
      + `fill="white"/><rect x="${x}" y="${y}" width="${w}" height="${h}" rx="8" fill="black"/>`
      + `</mask><rect x="0" y="0" width="${ctx.width}" height="${ctx.height}" fill="black" `
      + `fill-opacity="${dim}" mask="url(#spot${i})"/>`;
  },
};

export function buildSvg({ base, width, height, annotations, palette, scale = 2 }) {
  if (!Array.isArray(annotations)) throw invalid('annotations');
  const colours = resolvePalette(palette);
  const uri = `data:image/png;base64,${base.toString('base64')}`;
  let counter = 0;
  // One shared counter across blur and spotlight, matching the source script.
  // Note this is for fidelity and predictability, not collision avoidance:
  // the clip/blur and spot prefixes already keep the id strings distinct, so
  // per-type counters would not actually collide. Kept shared so the emitted
  // ids stay stable and comparable against the reference implementation.
  const ctx = { ...colours, uri, width, height, nextId: () => { counter += 1; return counter; } };

  const parts = [
    `<svg xmlns="http://www.w3.org/2000/svg" width="${width * scale}" `
    + `height="${height * scale}" viewBox="0 0 ${width} ${height}">`,
    '<defs><marker id="head" viewBox="0 0 10 10" refX="7" refY="5" '
    + 'markerWidth="5.5" markerHeight="5.5" orient="auto-start-reverse">'
    + `<path d="M 0 0 L 10 5 L 0 10 z" fill="${colours.accent}"/></marker>`
    + '<filter id="sh" x="-30%" y="-30%" width="160%" height="160%">'
    + '<feDropShadow dx="0" dy="2" stdDeviation="3" flood-opacity="0.35"/>'
    + '</filter></defs>',
    `<image href="${uri}" x="0" y="0" width="${width}" height="${height}"/>`,
  ];
  for (const annotation of annotations) {
    const draw = Object.hasOwn(DRAW, annotation?.type ?? '') ? DRAW[annotation.type] : null;
    if (!draw) {
      throw new LifecycleError('unsupported annotation type', {
        stage: 'validate',
        exitCode: 2,
      });
    }
    parts.push(draw(annotation, ctx));
  }
  parts.push('</svg>');
  return parts.join('');
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm run test:unit -- --test-name-pattern="svg|primitive|chip|counter|highlight|blur|annotation"`
Expected: PASS, 9 tests

- [ ] **Step 5: Commit**

```bash
git add lib/annotate/svg.mjs tests/unit/annotate-svg.test.mjs
git commit -m "feat(fast-browser): build annotation SVG from validated primitives"
```

---

### Task 4: rsvg-convert renderer, piped not written

**Files:**
- Create: `lib/annotate/render.mjs`
- Test: `tests/unit/annotate-render.test.mjs`

**Interfaces:**
- Consumes: nothing
- Produces: `RENDERER_BINARY` (string `'rsvg-convert'`), `rasterise({ svg, outPath, spawn, timeoutMs }) -> Promise<void>`, `rendererVersion({ spawn }) -> Promise<string|null>`

- [ ] **Step 1: Write the failing test**

```js
// tests/unit/annotate-render.test.mjs
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import test from 'node:test';

import { rasterise, rendererVersion } from '../../lib/annotate/render.mjs';

function fakeSpawn({ code = 0, error = null, capture = {} } = {}) {
  return () => {
    const child = new EventEmitter();
    child.stdin = { chunks: [], write(c) { this.chunks.push(c); }, end() { capture.svg = this.chunks.join(''); } };
    child.stdout = new EventEmitter();
    child.stderr = new EventEmitter();
    child.kill = () => { capture.killed = true; };
    queueMicrotask(() => {
      if (error) child.emit('error', error);
      else child.emit('close', code);
    });
    return child;
  };
}

test('the svg is piped to stdin and never written to disk', async () => {
  const capture = {};
  await rasterise({ svg: '<svg/>', outPath: '/tmp/out.png', spawn: fakeSpawn({ capture }) });
  assert.equal(capture.svg, '<svg/>');
});

test('a missing rsvg-convert reports the brew remediation', async () => {
  const enoent = Object.assign(new Error('spawn rsvg-convert ENOENT'), { code: 'ENOENT' });
  await assert.rejects(
    () => rasterise({ svg: '<svg/>', outPath: '/tmp/o.png', spawn: fakeSpawn({ error: enoent }) }),
    /brew install librsvg/,
  );
});

test('a non-zero exit fails rather than leaving a partial file', async () => {
  await assert.rejects(
    () => rasterise({ svg: '<svg/>', outPath: '/tmp/o.png', spawn: fakeSpawn({ code: 1 }) }),
    /rsvg-convert failed/,
  );
});

test('rendererVersion returns null when the binary is absent', async () => {
  const enoent = Object.assign(new Error('ENOENT'), { code: 'ENOENT' });
  assert.equal(await rendererVersion({ spawn: fakeSpawn({ error: enoent }) }), null);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm run test:unit -- --test-name-pattern="rsvg|renderer|piped"`
Expected: FAIL, cannot find module `lib/annotate/render.mjs`

- [ ] **Step 3: Write minimal implementation**

```js
// lib/annotate/render.mjs
import { spawn as nodeSpawn } from 'node:child_process';
import { rm } from 'node:fs/promises';

import { LifecycleError } from '../commands/shared.mjs';

export const RENDERER_BINARY = 'rsvg-convert';
const DEFAULT_TIMEOUT_MS = 20_000;
const MISSING = `${RENDERER_BINARY} is not installed; run \`brew install librsvg\``;

// The SVG embeds the full, unredacted base screenshot as base64. The source
// annotator wrote it beside its output and unlinked it only on success, so a
// crash between write and rasterise left an un-redacted copy on disk. Piping
// through stdin means it never exists as a file.
export async function rasterise({
  svg,
  outPath,
  spawn = nodeSpawn,
  timeoutMs = DEFAULT_TIMEOUT_MS,
}) {
  await new Promise((resolve, reject) => {
    const child = spawn(RENDERER_BINARY, ['--output', outPath, '--format', 'png', '-'], {
      stdio: ['pipe', 'ignore', 'pipe'],
    });
    // An SVG with a base64 screenshot in it far exceeds the 64KB pipe buffer,
    // so the write below is always still in flight. If the child then exits
    // early, or the timeout below SIGKILLs it, the write fails with EPIPE, and
    // an unhandled 'error' on a stream is an UNCAUGHT EXCEPTION that kills the
    // host process rather than rejecting this promise. Rejection is already
    // driven by the 'error' and 'close' handlers on `child`, so there is
    // nothing this handler needs to report.
    child.stdin.on('error', () => {});
    const timer = setTimeout(() => {
      child.kill('SIGKILL');
      reject(new LifecycleError(`${RENDERER_BINARY} timed out`, { stage: 'render' }));
    }, timeoutMs);
    timer.unref?.();

    child.on('error', (error) => {
      clearTimeout(timer);
      reject(error?.code === 'ENOENT'
        ? new LifecycleError(MISSING, { stage: 'render', exitCode: 2 })
        : new LifecycleError(`${RENDERER_BINARY} could not be started`, { stage: 'render' }));
    });
    child.on('close', (code) => {
      clearTimeout(timer);
      if (code === 0) resolve();
      else reject(new LifecycleError(`${RENDERER_BINARY} failed`, { stage: 'render' }));
    });
    child.stdin.write(svg);
    child.stdin.end();
  }).catch(async (error) => {
    // A failed or killed rsvg can leave a zero-length or half-written PNG.
    await rm(outPath, { force: true }).catch(() => {});
    throw error;
  });
}

export async function rendererVersion({ spawn = nodeSpawn } = {}) {
  return new Promise((resolve) => {
    let output = '';
    let child;
    try {
      child = spawn(RENDERER_BINARY, ['--version'], { stdio: ['ignore', 'pipe', 'ignore'] });
    } catch {
      resolve(null);
      return;
    }
    child.stdout?.on('data', (chunk) => { output += String(chunk); });
    child.on('error', () => resolve(null));
    child.on('close', (code) => resolve(code === 0 ? output.trim().split('\n')[0] : null));
  });
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm run test:unit -- --test-name-pattern="rsvg|renderer|piped|partial"`
Expected: PASS, 4 tests

- [ ] **Step 5: Commit**

```bash
git add lib/annotate/render.mjs tests/unit/annotate-render.test.mjs
git commit -m "feat(fast-browser): rasterise annotations via piped rsvg-convert"
```

---

### Task 5: Config gains `annotation.palette`

**Files:**
- Modify: `lib/core/config.mjs:15-26` (`defaultConfig`), `lib/core/config.mjs:120-142` (`parseConfig` return)
- Test: `tests/unit/config.test.mjs` (append)

**Interfaces:**
- Consumes: `RADIX_SCALES` (Task 1)
- Produces: `config.annotation.palette` is `string | null`; `null` means the user has not chosen yet

- [ ] **Step 1: Write the failing test**

```js
// append to tests/unit/config.test.mjs
test('annotation palette defaults to unset so the first use must choose', () => {
  assert.equal(defaultConfig().annotation.palette, null);
});

test('an existing v1 config without an annotation block still parses', () => {
  const legacy = defaultConfig();
  delete legacy.annotation;
  assert.equal(parseConfig(legacy).annotation.palette, null);
});

test('a stored palette round-trips and an invalid one is refused', () => {
  const config = { ...defaultConfig(), annotation: { palette: 'teal' } };
  assert.equal(parseConfig(config).annotation.palette, 'teal');
  assert.throws(
    () => parseConfig({ ...defaultConfig(), annotation: { palette: 'burgundy' } }),
    /annotation.palette/,
  );
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm run test:unit -- --test-name-pattern="annotation palette|annotation block"`
Expected: FAIL, `defaultConfig().annotation` is undefined

- [ ] **Step 3: Write minimal implementation**

In `lib/core/config.mjs`, add the import at the top:

```js
import { RADIX_SCALES } from '../annotate/palette.mjs';
```

Add to `defaultConfig()`'s returned object, after `sessions`:

```js
    annotation: { palette: null },
```

Add this helper next to the other validators:

```js
// Absent means "the user has not chosen a palette yet", which is distinct from
// any valid scale name. No schemaVersion bump is needed: parseConfig rebuilds
// its result from known keys, so a stored v1 config that predates this field
// simply reads as unset.
function annotationPalette(value, field) {
  if (value === null || value === undefined) return null;
  if (typeof value !== 'string' || !Object.hasOwn(RADIX_SCALES, value)) {
    throw new ConfigError(`${field} must be a Radix colour scale name`);
  }
  return value;
}
```

In `parseConfig`, before the return, add:

```js
  const annotation = config.annotation === undefined
    ? {}
    : object(config.annotation, 'annotation');
```

And add to the returned object, after `sessions`:

```js
    annotation: {
      palette: annotationPalette(annotation.palette, 'annotation.palette'),
    },
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test`
Expected: PASS, full suite green (config is read by many tests, so run all of it)

- [ ] **Step 5: Commit**

```bash
git add lib/core/config.mjs tests/unit/config.test.mjs
git commit -m "feat(fast-browser): store the annotation palette in config"
```

---

### Task 6: `configure --palette` without side effects

**Files:**
- Modify: `lib/cli/parse-args.mjs` (add `--palette`), `lib/commands/configure.mjs:77-89`
- Test: `tests/unit/parse-args.test.mjs` (append), `tests/unit/commands.test.mjs` (append)

**Interfaces:**
- Consumes: `RADIX_SCALES` (Task 1), `config.annotation.palette` (Task 5)
- Produces: `request.palette` is `string | null`; `configure` persists it without touching sessions, profile or routing

**Why this task exists:** `configure` currently recomputes session settings from *profile defaults*, not from the current config:

```js
const days = retentionDays(request.retentionDays ?? defaults.retentionDays);
const enabled = request.recordSessions ?? defaults.enabled;
```

`profileDefaults('full')` returns `{ enabled: true, retentionDays: 30 }`. Without this fix, a full-profile user who ran `--no-record-sessions` and later set a palette would have session recording silently switched back on. Choosing a colour must not change privacy settings.

- [ ] **Step 1: Write the failing test**

```js
// append to tests/unit/parse-args.test.mjs
test('--palette is accepted for configure and validated', () => {
  assert.equal(parseArgs(['configure', '--palette', 'teal']).palette, 'teal');
  assert.throws(() => parseArgs(['configure', '--palette', 'burgundy']), UsageError);
  assert.throws(() => parseArgs(['setup', '--palette', 'teal']), UsageError);
});

// append to tests/unit/commands.test.mjs
// Dependency names must match lib/commands/configure.mjs `dependencies()`:
// loadConfig, saveConfig, prepareRoutingTransition, getCodexVersion.
//
// Do NOT build a request with `{ ...parseArgs(...), json: true }`. parseArgs
// defines `explicitOptions` as a NON-ENUMERABLE property, so object spread
// silently drops it, defeating both the paletteOnly shortcut and
// selectedProfile while the test still appears to run. Mutate .json in place
// on the parsed request instead, or pass --json through argv.
test('configure --palette preserves session settings and profile', async () => {
  const stored = {
    ...defaultConfig(),
    profile: 'full',
    sessions: { enabled: false, retentionDays: 90 },
  };
  let written = null;
  await configure(
    { ...parseArgs(['configure', '--palette', 'teal']), json: true },
    {
      paths: { dataDir: '/tmp/fb', configFile: '/tmp/fb/config.json' },
      loadConfig: async () => stored,
      saveConfig: async (_paths, value) => { written = value; },
      prepareRoutingTransition: async () => assert.fail(
        'routing must not run for --palette alone',
      ),
      pruneSessions: async () => ({ removedPaths: [], removedBytes: 0 }),
    },
  );
  assert.equal(written.annotation.palette, 'teal');
  assert.equal(written.sessions.enabled, false, 'recording must not be re-enabled');
  assert.equal(written.sessions.retentionDays, 90, 'retention must not be reset');
  assert.equal(written.profile, 'full');
});

test('configure --palette does not require Codex detection', async () => {
  await configure(
    { ...parseArgs(['configure', '--palette', 'iris']), json: true },
    {
      paths: { dataDir: '/tmp/fb', configFile: '/tmp/fb/config.json' },
      loadConfig: async () => ({ ...defaultConfig(), hosts: { claude: false, codex: true } }),
      saveConfig: async () => {},
      prepareRoutingTransition: async () => assert.fail('routing must not run'),
      getCodexVersion: async () => assert.fail('Codex detection must not run for --palette'),
      pruneSessions: async () => ({ removedPaths: [], removedBytes: 0 }),
    },
  );
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm run test:unit -- --test-name-pattern="palette"`
Expected: FAIL, `--palette` is an unsupported argument

- [ ] **Step 3: Write minimal implementation**

In `lib/cli/parse-args.mjs`, add the import:

```js
import { RADIX_SCALES } from '../annotate/palette.mjs';
```

Add `palette: null,` to the object returned by `requestFor()`. Add this case to the switch, before `default`:

```js
      case '--palette': {
        requireCommand(command, ['configure'], token);
        const palette = valueFor(arguments_, index, token);
        if (!Object.hasOwn(RADIX_SCALES, palette)) {
          throw new UsageError(token, `invalid value for ${token}`);
        }
        request.palette = palette;
        index += 1;
        break;
      }
```

In `lib/commands/configure.mjs`, replace lines 80-83:

```js
  const profile = selectedProfile(request, current);
  const defaults = profileDefaults(profile);
  const days = retentionDays(request.retentionDays ?? defaults.retentionDays);
  const enabled = request.recordSessions ?? defaults.enabled;
```

with:

```js
  const profile = selectedProfile(request, current);
  const defaults = profileDefaults(profile);
  // Fall back to the CURRENT config, not to profile defaults. Falling back to
  // defaults means any unrelated `configure` invocation silently resets session
  // recording and retention, so setting a palette could re-enable recording for
  // a user who had deliberately turned it off.
  const profileChanged = profile !== current.profile;
  const sessionFallback = profileChanged ? defaults : current.sessions;
  const days = retentionDays(request.retentionDays ?? sessionFallback.retentionDays);
  const enabled = request.recordSessions ?? sessionFallback.enabled;
  const palette = request.palette ?? current.annotation.palette;
  // A palette-only invocation touches one scalar in config.json. Running the
  // host routing transition for it would also demand Codex CLI detection, so
  // `--palette` would fail outright on a machine where Codex was set up and
  // later removed.
  // `--json` is an output-format flag, not a configuration change, so it must
  // not count toward the shortcut: agents routinely run
  // `configure --palette teal --json`, and counting it would take the full
  // routing path and reintroduce the Codex-detection failure this exists to
  // avoid.
  const changing = [...(request.explicitOptions ?? [])].filter((o) => o !== '--json');
  const paletteOnly = changing.length === 1 && changing[0] === '--palette';
```

Guard the routing transition and persist the palette. Where `configure` currently builds the config to write, include:

```js
    annotation: { palette },
```

and wrap the routing call:

```js
  if (!paletteOnly) {
    // existing routing transition, unchanged
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test`
Expected: PASS, full suite green

- [ ] **Step 5: Commit**

```bash
git add lib/cli/parse-args.mjs lib/commands/configure.mjs tests/unit/parse-args.test.mjs tests/unit/commands.test.mjs
git commit -m "fix(fast-browser): keep configure from resetting sessions on unrelated changes"
```

---

### Task 7: `annotate` command parsing with a positional argument

**Files:**
- Modify: `lib/cli/parse-args.mjs:1` (`COMMANDS`), `lib/cli/parse-args.mjs:89-184` (loop)
- Test: `tests/unit/parse-args.test.mjs` (append)

**Interfaces:**
- Consumes: nothing
- Produces: `request.command === 'annotate'`, `request.config` (string, the positional config path)

**Why this needs new machinery:** the parser's `default:` branch throws `UsageError` on any token that is not a recognised flag, so there is currently no way to pass a positional argument.

- [ ] **Step 1: Write the failing test**

```js
// append to tests/unit/parse-args.test.mjs
test('annotate takes exactly one positional config path', () => {
  const request = parseArgs(['annotate', 'shot.json']);
  assert.equal(request.command, 'annotate');
  assert.equal(request.config, 'shot.json');
});

test('annotate accepts --json alongside the positional', () => {
  const request = parseArgs(['annotate', 'shot.json', '--json']);
  assert.equal(request.config, 'shot.json');
  assert.equal(request.json, true);
});

test('annotate rejects a missing, duplicated, or flag-like positional', () => {
  assert.throws(() => parseArgs(['annotate']), UsageError);
  assert.throws(() => parseArgs(['annotate', 'a.json', 'b.json']), UsageError);
  assert.throws(() => parseArgs(['annotate', '--nope']), UsageError);
});

test('other commands still reject positional arguments', () => {
  assert.throws(() => parseArgs(['doctor', 'extra']), UsageError);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm run test:unit -- --test-name-pattern="annotate"`
Expected: FAIL, `expected a command`

- [ ] **Step 3: Write minimal implementation**

In `lib/cli/parse-args.mjs`:

```js
const COMMANDS = new Set(['setup', 'doctor', 'configure', 'migrate', 'uninstall', 'annotate']);
```

Add `config: null,` to `requestFor()`'s returned object.

Replace the `default:` case in the switch with:

```js
      default: {
        // `annotate` is the only command taking a positional. Everything else
        // keeps the strict flags-only contract.
        if (command !== 'annotate' || token.startsWith('--')) throw new UsageError(token);
        if (request.config !== null) {
          throw new UsageError(token, 'annotate takes exactly one config path');
        }
        request.config = token;
        break;
      }
```

IMPORTANT: check `request.config !== null` BEFORE the shared `seen` logic runs
for a positional token. The existing `duplicate option: ${token}` throw at the
top of the loop interpolates the token RAW, and was safe only because a
non-flag token could never reach it twice: it always threw through the
sanitised fallback on first sight. A positional breaks that invariant and would
leak a user-supplied path into an error message, which the file deliberately
prevents everywhere else via `safeToken()`. Route a duplicate positional through
the sanitised "exactly one config path" message instead. Do not wrap line 95's
token in `safeToken()`; that would degrade legitimate duplicate-FLAG messages.

After the loop, before the existing conflict check, add:

```js
  if (command === 'annotate' && request.config === null) {
    throw new UsageError('<config>', 'annotate requires a config path');
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test`
Expected: PASS, full suite green

- [ ] **Step 5: Commit**

```bash
git add lib/cli/parse-args.mjs tests/unit/parse-args.test.mjs
git commit -m "feat(fast-browser): parse the annotate command and its config path"
```

---

### Task 8: The `annotate` command

**Files:**
- Create: `lib/commands/annotate.mjs`
- Modify: `lib/core/paths.mjs:10-24` (add `screenshotsDir`), `lib/cli/main.mjs:1-10` and `:88-110` and `:122-128`
- Test: `tests/unit/paths.test.mjs` (append), `tests/integration/annotate.test.mjs` (create)

**Interfaces:**
- Consumes: `readPngSize` (Task 2), `buildSvg` (Task 3), `rasterise` (Task 4), `resolvePalette`/`OFFERED_PALETTES` (Task 1), `config.annotation.palette` (Task 5)
- Produces: `annotate(request, dependencies) -> { out, base, annotations, palette, width, height }`

**Config file shape consumed by the command:**

```json
{
  "base": "claim-detail.png",
  "out": "claim-detail-annotated.png",
  "scale": 2,
  "measured": {
    "schemaVersion": 1,
    "viewport": { "inner": [900, 560], "client": [885, 560] }
  },
  "annotations": [
    { "type": "highlight", "box": [783, 200, 72, 17] },
    { "type": "blur", "box": [320, 128, 99, 17] }
  ]
}
```

`base` and `out` are **names, not paths**: both resolve inside `paths.screenshotsDir`. Containment wins over caller-chosen locations.

- [ ] **Step 1: Write the failing test**

```js
// tests/integration/annotate.test.mjs
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, readFile, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';

import { annotate } from '../../lib/commands/annotate.mjs';
import { defaultConfig } from '../../lib/core/config.mjs';
import { resolvePaths } from '../../lib/core/paths.mjs';

function pngBytes(width, height) {
  const buffer = Buffer.alloc(24);
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]).copy(buffer, 0);
  buffer.write('IHDR', 12, 'latin1');
  buffer.writeUInt32BE(width, 16);
  buffer.writeUInt32BE(height, 20);
  return buffer;
}

async function fixture(configBody, { palette = 'violet' } = {}) {
  const homeDir = await mkdtemp(path.join(tmpdir(), 'fb-annot-'));
  const paths = resolvePaths({ homeDir, pluginRoot: process.cwd() });
  await mkdir(paths.screenshotsDir, { recursive: true });
  await writeFile(path.join(paths.screenshotsDir, 'base.png'), pngBytes(900, 560));
  const configPath = path.join(homeDir, 'annot.json');
  await writeFile(configPath, JSON.stringify(configBody));
  return {
    paths,
    configPath,
    config: { ...defaultConfig(), annotation: { palette } },
  };
}

const BODY = {
  base: 'base.png',
  out: 'base-annotated.png',
  measured: { schemaVersion: 1, viewport: { inner: [900, 560], client: [900, 560] } },
  annotations: [{ type: 'highlight', box: [783, 200, 72, 17] }],
};

test('annotate rasterises to the screenshots directory', async () => {
  const { paths, configPath, config } = await fixture(BODY);
  let rendered = null;
  const report = await annotate(
    { command: 'annotate', config: configPath, json: true },
    {
      paths,
      loadConfig: async () => config,
      rasterise: async ({ svg, outPath }) => { rendered = { svg, outPath }; },
    },
  );
  assert.equal(report.out, path.join(paths.screenshotsDir, 'base-annotated.png'));
  assert.equal(rendered.outPath, report.out);
  assert.match(rendered.svg, /viewBox="0 0 900 560"/);
});

test('annotate refuses when no palette has been chosen', async () => {
  const { paths, configPath, config } = await fixture(BODY, { palette: null });
  await assert.rejects(
    () => annotate({ command: 'annotate', config: configPath }, {
      paths, loadConfig: async () => config, rasterise: async () => {},
    }),
    /fast-browser configure --palette/,
  );
});

test('annotate refuses a box that extends past the image', async () => {
  const { paths, configPath, config } = await fixture({
    ...BODY,
    annotations: [{ type: 'blur', box: [860, 200, 100, 17] }],
  });
  await assert.rejects(
    () => annotate({ command: 'annotate', config: configPath }, {
      paths, loadConfig: async () => config, rasterise: async () => {},
    }),
    /outside the image/,
  );
});

test('annotate refuses an unversioned measurement payload', async () => {
  const { paths, configPath, config } = await fixture({
    ...BODY, measured: { viewport: { inner: [900, 560], client: [900, 560] } },
  });
  await assert.rejects(
    () => annotate({ command: 'annotate', config: configPath }, {
      paths, loadConfig: async () => config, rasterise: async () => {},
    }),
    /measurement payload/,
  );
});

test('annotate refuses when the PNG matches neither reported viewport width', async () => {
  const { paths, configPath, config } = await fixture({
    ...BODY, measured: { schemaVersion: 1, viewport: { inner: [1280, 560], client: [1265, 560] } },
  });
  await assert.rejects(
    () => annotate({ command: 'annotate', config: configPath }, {
      paths, loadConfig: async () => config, rasterise: async () => {},
    }),
    /does not match the measured viewport/,
  );
});

test('annotate refuses to overwrite its own base', async () => {
  const { paths, configPath, config } = await fixture({ ...BODY, out: 'base.png' });
  await assert.rejects(
    () => annotate({ command: 'annotate', config: configPath }, {
      paths, loadConfig: async () => config, rasterise: async () => {},
    }),
    /must not overwrite/,
  );
});

test('annotate refuses a base or out that escapes the screenshots directory', async () => {
  for (const escape of ['../config.json', '/etc/passwd']) {
    const { paths, configPath, config } = await fixture({ ...BODY, out: escape });
    await assert.rejects(
      () => annotate({ command: 'annotate', config: configPath }, {
        paths, loadConfig: async () => config, rasterise: async () => {},
      }),
    );
  }
});

// append to tests/unit/paths.test.mjs
test('screenshotsDir is an exact data-directory child', () => {
  const paths = resolvePaths({ homeDir: '/tmp/fb-home', pluginRoot: '/plugin' });
  assert.equal(paths.screenshotsDir, '/tmp/fb-home/.fast-browser/screenshots');
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm run test:integration -- --test-name-pattern="annotate"`
Expected: FAIL, cannot find module `lib/commands/annotate.mjs`

- [ ] **Step 3: Write minimal implementation**

Add to `lib/core/paths.mjs`'s returned object:

```js
    screenshotsDir: path.join(dataDir, 'screenshots'),
```

Create `lib/commands/annotate.mjs`:

```js
import { mkdir, readFile } from 'node:fs/promises';
import path from 'node:path';

import { OFFERED_PALETTES } from '../annotate/palette.mjs';
import { readPngSize } from '../annotate/png.mjs';
import { rasterise as defaultRasterise } from '../annotate/render.mjs';
import { buildSvg } from '../annotate/svg.mjs';
import { assertConfinedPath } from '../core/containment.mjs';
import { loadConfig as defaultLoadConfig } from '../core/config.mjs';
import { LifecycleError } from './shared.mjs';

const MEASUREMENT_SCHEMA_VERSION = 1;

function fail(message, exitCode = 2) {
  return new LifecycleError(message, { stage: 'annotate', exitCode });
}

// `base` and `out` are names inside the screenshots directory, never paths.
// assertConfinedPath structurally requires its root to sit under dataDir, so
// honouring caller-chosen absolute paths and confining are mutually exclusive;
// containment wins.
async function confinedName(paths, name, field) {
  if (typeof name !== 'string' || name.length === 0) throw fail(`${field} is required`);
  const candidate = path.resolve(paths.screenshotsDir, name);
  await assertConfinedPath({
    dataDir: paths.dataDir,
    rootDir: paths.screenshotsDir,
    candidate,
  });
  return candidate;
}

function assertMeasurement(measured, width) {
  if (!measured || measured.schemaVersion !== MEASUREMENT_SCHEMA_VERSION) {
    throw fail(
      'unsupported measurement payload; remove ~/.fast-browser/macros/capture-annotated.js '
      + 'and run `fast-browser setup` to reinstall it',
    );
  }
  const inner = measured.viewport?.inner?.[0];
  const client = measured.viewport?.client?.[0];
  // Corroboration only. Atomic capture-and-measure is what makes the
  // coordinates trustworthy; this catches a base swapped out from under the
  // config. innerWidth alone cannot see a classic scrollbar because it counts
  // the scrollbar's own pixels, which is why both widths are checked.
  if (width !== inner && width !== client) {
    throw fail(
      `the base image width ${width} does not match the measured viewport `
      + `(inner ${inner}, client ${client})`,
    );
  }
}

function assertInBounds(annotations, width, height) {
  const corners = (a) => {
    if (Array.isArray(a.box)) return [[a.box[0], a.box[1]], [a.box[0] + a.box[2], a.box[1] + a.box[3]]];
    if (a.type === 'ellipse') {
      return [[a.cx - a.rx, a.cy - (a.ry ?? a.rx)], [a.cx + a.rx, a.cy + (a.ry ?? a.rx)]];
    }
    return [];
  };
  for (const [index, annotation] of annotations.entries()) {
    for (const [x, y] of corners(annotation)) {
      if (x < 0 || y < 0 || x > width || y > height) {
        // boundingBox() returns real coordinates for elements below the fold.
        // SVG outside the viewBox rasterises to nothing, so without this a blur
        // silently covers nothing and the agent reports a redaction that is not
        // there.
        throw fail(
          `annotation ${index} (${annotation.type}) falls outside the image `
          + `(${width}x${height}); it was probably measured out of view`,
        );
      }
    }
  }
}

export async function annotate(request, supplied = {}) {
  const paths = supplied.paths;
  const loadConfig = supplied.loadConfig ?? defaultLoadConfig;
  const rasterise = supplied.rasterise ?? defaultRasterise;

  const config = await loadConfig(paths);
  const palette = config.annotation?.palette ?? null;
  if (!palette) {
    throw fail(
      'no annotation palette is configured. Choose one of '
      + `${OFFERED_PALETTES.join(', ')} with \`fast-browser configure --palette <name>\``,
    );
  }

  let body;
  try {
    body = JSON.parse(await readFile(request.config, 'utf8'));
  } catch {
    throw fail('unable to read the annotation config');
  }
  if (!Array.isArray(body.annotations) || body.annotations.length === 0) {
    throw fail('the annotation config lists no annotations');
  }

  const basePath = await confinedName(paths, body.base, 'base');
  const outPath = await confinedName(paths, body.out, 'out');
  if (basePath === outPath) throw fail('out must not overwrite the base capture');

  const base = await readFile(basePath);
  const { width, height } = readPngSize(base);
  assertMeasurement(body.measured, width);
  assertInBounds(body.annotations, width, height);

  const scale = body.scale === undefined ? 2 : body.scale;
  if (!Number.isInteger(scale) || scale < 1 || scale > 4) throw fail('scale must be 1 to 4');

  const svg = buildSvg({
    base, width, height, annotations: body.annotations, palette, scale,
  });
  await mkdir(paths.screenshotsDir, { recursive: true, mode: 0o700 });
  await rasterise({ svg, outPath });

  return {
    base: basePath,
    out: outPath,
    palette,
    annotations: body.annotations.length,
    width: width * scale,
    height: height * scale,
  };
}
```

In `lib/cli/main.mjs`, add the import:

```js
import { annotate } from '../commands/annotate.mjs';
```

Add `annotate,` to the `commands` object. Add to `humanReport`, before the final `return '':`

```js
  if (command === 'annotate') {
    return `Annotated ${report.annotations} region${report.annotations === 1 ? '' : 's'} `
      + `at ${report.width}x${report.height}: ${report.out}\n`;
  }
```

Update `HELP` to list `annotate`:

```js
const HELP = [
  'Usage: fast-browser <setup|doctor|configure|migrate|uninstall|annotate> [options]',
  'Run `fast-browser <command> --help` for command options.',
].join('\n');
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test`
Expected: PASS, full suite green

- [ ] **Step 5: Commit**

```bash
git add lib/commands/annotate.mjs lib/core/paths.mjs lib/cli/main.mjs tests/integration/annotate.test.mjs tests/unit/paths.test.mjs
git commit -m "feat(fast-browser): add the annotate command"
```

---

### Task 9: Capture-and-measure macro, and a multi-builtin installer

**Files:**
- Create: `builtins/macros/capture-annotated.js`
- Modify: `lib/macros/install.mjs` (generalise from one builtin to a list), `skills/browser-macros/MACROS.md` (add the index entry)
- Test: `tests/unit/macros.test.mjs` (extend)

**Interfaces:**
- Consumes: nothing
- Produces: macro returning `{ schemaVersion: 1, png, viewport: { inner, client }, resolved, missed }`

**Why capture and measure are one call:** splitting them across two MCP tool calls puts an agent turn between them. Any reflow in that window (a lazy image, a font swap, a dismissed toast) means the boxes describe a layout the PNG does not show. No equality check closes that gap.

- [ ] **Step 1: Write the failing test**

```js
// append to tests/unit/macros.test.mjs
test('both builtin macros install and appear in the index', async (t) => {
  const { paths } = await macroFixture(t);
  await installBuiltinMacros(paths);
  for (const name of ['page-recon.js', 'capture-annotated.js']) {
    const state = await lstat(path.join(paths.macrosDir, name));
    assert.equal(state.isFile(), true, name);
  }
  const index = await readFile(paths.macroIndexFile, 'utf8');
  assert.match(index, /^## page-recon$/m);
  assert.match(index, /^## capture-annotated$/m);
});

test('installing twice does not duplicate index sections or overwrite edits', async (t) => {
  const { paths } = await macroFixture(t);
  await installBuiltinMacros(paths);
  await writeFile(path.join(paths.macrosDir, 'capture-annotated.js'), '// user edit\n');
  await installBuiltinMacros(paths);
  const index = await readFile(paths.macroIndexFile, 'utf8');
  assert.equal(index.match(/^## capture-annotated$/gm).length, 1);
  assert.equal(
    await readFile(path.join(paths.macrosDir, 'capture-annotated.js'), 'utf8'),
    '// user edit\n',
    'a user-edited macro is never overwritten',
  );
});

test('a macro index missing only one section gains just that section', async (t) => {
  const { paths } = await macroFixture(t);
  await mkdir(paths.macrosDir, { recursive: true, mode: 0o700 });
  await writeFile(paths.macroIndexFile, '# Macro Index\n\n## page-recon\n\n- Status: built-in\n');
  await installBuiltinMacros(paths);
  const index = await readFile(paths.macroIndexFile, 'utf8');
  assert.equal(index.match(/^## page-recon$/gm).length, 1);
  assert.equal(index.match(/^## capture-annotated$/gm).length, 1);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm run test:unit -- --test-name-pattern="builtin macros|index section"`
Expected: FAIL, `capture-annotated.js` does not exist

- [ ] **Step 3: Write the macro**

```js
// builtins/macros/capture-annotated.js
async (page, args) => {
  const { targets = {}, out = 'capture' } = args || {};
  const names = Object.keys(targets);
  if (names.length === 0) {
    return { failedStep: 'args', error: 'targets is required' };
  }
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/.test(out)) {
    return { failedStep: 'args', error: 'out must be a simple file name' };
  }

  const home = process.env.HOME;
  // `name` is what goes into the annotate config's `base` field, which takes a
  // NAME inside the screenshots directory, not a path. Returning both avoids
  // the agent having to derive one from the other and getting it wrong.
  const name = `${out}.png`;
  const png = `${home}/.fast-browser/screenshots/${name}`;

  try {
    // Screenshot FIRST, then measure, with nothing between them that could
    // reflow the page. This adjacency is the entire integrity guarantee: any
    // gap lets a lazy image or a dismissing toast move the elements, and the
    // boxes would then describe a layout the PNG does not show.
    await page.screenshot({ path: png, scale: 'css' });

    const viewport = await page.evaluate(() => ({
      inner: [window.innerWidth, window.innerHeight],
      // innerWidth counts a classic scrollbar's own pixels, so it cannot
      // detect one. clientWidth is what changes when a scrollbar appears.
      client: [document.documentElement.clientWidth, document.documentElement.clientHeight],
    }));

    const resolved = {};
    const missed = [];
    for (const name of names) {
      const selector = targets[name];
      const locator = page.locator(selector);
      const count = await locator.count();
      if (count === 0) {
        missed.push({ key: name, reason: 'no-match' });
        continue;
      }
      if (count > 1) {
        // Never take the first hit. Silently annotating element 1 of 4 is how
        // a redaction lands on the wrong row.
        missed.push({ key: name, reason: 'ambiguous', count });
        continue;
      }
      const box = await locator.boundingBox();
      if (!box || box.width <= 0 || box.height <= 0) {
        missed.push({ key: name, reason: 'not-visible' });
        continue;
      }
      const rect = [
        Math.round(box.x), Math.round(box.y),
        Math.round(box.width), Math.round(box.height),
      ];
      if (
        rect[0] < 0 || rect[1] < 0
        || rect[0] + rect[2] > viewport.inner[0]
        || rect[1] + rect[3] > viewport.inner[1]
      ) {
        missed.push({ key: name, reason: 'out-of-view' });
        continue;
      }
      resolved[name] = rect;
    }

    // Playwright creates parent directories for a screenshot path, so the
    // screenshots directory does not need to exist beforehand.
    return { schemaVersion: 1, name, png, viewport, resolved, missed };
  } catch (error) {
    return { failedStep: 'capture', error: String(error && error.message), url: page.url() };
  }
}
```

- [ ] **Step 4: Generalise the installer**

In `lib/macros/install.mjs`, replace the single-builtin constants:

```js
const BUILTIN_NAME = 'page-recon.js';
```

with:

```js
// Every built-in macro ships as a file plus a `## <name>` section in the
// packaged index. Both are installed without overwriting anything the user has
// since edited.
const BUILTIN_NAMES = Object.freeze(['page-recon.js', 'capture-annotated.js']);
```

Replace `pageReconSection` with a name-keyed extractor:

```js
function indexSection(template, macroName) {
  const heading = new RegExp(`^## ${macroName}[ \\t]*$`, 'm');
  const start = template.search(heading);
  if (start < 0) throw new Error(`packaged macro index is missing ${macroName}`);
  const next = template.slice(start + 1).search(/^## /m);
  const end = next < 0 ? template.length : start + 1 + next;
  return template.slice(start, end).trimEnd();
}
```

Replace `ensureLiveIndex` so it merges every missing section rather than only `page-recon`:

```js
async function ensureLiveIndex(indexFile, template) {
  const macroNames = BUILTIN_NAMES.map((file) => file.replace(/\.js$/, ''));
  for (let attempt = 0; attempt < 2; attempt += 1) {
    const state = await lstatOrNull(indexFile);
    if (!state) {
      try {
        await createWithoutOverwrite(indexFile, template, 0o600);
        return;
      } catch (error) {
        if (error?.code === 'EEXIST') continue;
        throw error;
      }
    }
    const original = await readRegularFile(
      indexFile,
      'live macro index must be a regular file',
    );
    const missing = macroNames.filter(
      (name) => !new RegExp(`^## ${name}[ \\t]*$`, 'm').test(original.text),
    );
    if (missing.length === 0) return;
    let merged = original.text;
    for (const name of missing) {
      const separator = merged.endsWith('\n\n') ? '' : merged.endsWith('\n') ? '\n' : '\n\n';
      merged = `${merged}${separator}${indexSection(template, name)}\n`;
    }
    await replaceUnchangedIndex(indexFile, original, merged);
    return;
  }
  throw new Error('live macro index changed during creation');
}
```

In `installBuiltinMacros`, replace the single destination with a loop over `BUILTIN_NAMES`, keeping `assertConfinedPath`, `copyWithoutOverwrite` and `verifyMacroFile` per file:

```js
  await Promise.all(BUILTIN_NAMES.map((name) => assertConfinedPath({
    dataDir, rootDir: macrosDir, candidate: path.join(macrosDir, name),
  })));
```

and after `ensureLiveIndex`:

```js
  for (const name of BUILTIN_NAMES) {
    const destination = path.join(macrosDir, name);
    await copyWithoutOverwrite(path.join(paths.pluginRoot, 'builtins', 'macros', name), destination);
    await verifyMacroFile(destination);
  }
```

- [ ] **Step 5: Add the index entry**

Append to `skills/browser-macros/MACROS.md`:

```markdown
## capture-annotated

- Description: Capture the viewport to a PNG and measure named CSS selectors to
  pixel boxes in the same page state, for use with `fast-browser annotate`.
  Returns resolved boxes plus a `missed` list naming any selector that did not
  match, matched more than once, or fell outside the viewport.
- Params: `{ targets: Record<string, string>, out?: string (default "capture") }`
- Target: Current page (site-agnostic)
- Script: `~/.fast-browser/macros/capture-annotated.js`
- Status: built-in
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `npm test`
Expected: PASS, full suite green

- [ ] **Step 7: Commit**

```bash
git add builtins/macros/capture-annotated.js lib/macros/install.mjs skills/browser-macros/MACROS.md tests/unit/macros.test.mjs
git commit -m "feat(fast-browser): add atomic capture-and-measure macro"
```

---

### Task 10: Doctor check for the renderer

**Files:**
- Modify: `lib/doctor/checks.mjs:4-23` (`DOCTOR_CHECK_IDS`), `lib/commands/doctor.mjs` (check registry)
- Test: `tests/unit/commands.test.mjs` (append)

**Interfaces:**
- Consumes: `rendererVersion` (Task 4)
- Produces: doctor check id `annotate-renderer`

- [ ] **Step 1: Write the failing test**

```js
// append to tests/unit/commands.test.mjs
test('doctor passes when rsvg-convert is present and names its version', async () => {
  const report = await doctor({ command: 'doctor', json: true }, {
    ...doctorStubs(),
    rendererVersion: async () => 'rsvg-convert version 2.62.1',
  });
  const check = report.checks.find(({ id }) => id === 'annotate-renderer');
  assert.equal(check.status, 'pass');
  assert.match(check.message, /2\.62\.1/);
});

test('doctor fails with the brew remediation when rsvg-convert is absent', async () => {
  const report = await doctor({ command: 'doctor', json: true }, {
    ...doctorStubs(),
    rendererVersion: async () => null,
  });
  const check = report.checks.find(({ id }) => id === 'annotate-renderer');
  assert.equal(check.status, 'fail');
  assert.match(check.remediation, /brew install librsvg/);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm run test:unit -- --test-name-pattern="rsvg-convert is"`
Expected: FAIL, no check with id `annotate-renderer`

- [ ] **Step 3: Write minimal implementation**

Add `'annotate-renderer',` to `DOCTOR_CHECK_IDS` in `lib/doctor/checks.mjs`, after `'tool-contract'`.

In `lib/commands/doctor.mjs`, add the import:

```js
import { rendererVersion } from '../annotate/render.mjs';
```

Add to the check registry object:

```js
    // Annotation is optional, so this is not required by setup. It fails only
    // to tell a user who wants annotation exactly what to install.
    'annotate-renderer': async () => {
      const version = await (dependencies.rendererVersion ?? rendererVersion)();
      return version
        ? pass(`Annotation renderer is available (${version}).`)
        : fail(
          'The annotation renderer is not installed.',
          'Run `brew install librsvg` to enable `fast-browser annotate`.',
        );
    },
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test`
Expected: PASS, full suite green

- [ ] **Step 5: Commit**

```bash
git add lib/doctor/checks.mjs lib/commands/doctor.mjs tests/unit/commands.test.mjs
git commit -m "feat(fast-browser): report annotation renderer status in doctor"
```

---

### Task 11: The `annotating-screenshots` skill

**Files:**
- Create: `skills/annotating-screenshots/SKILL.md`, `skills/annotating-screenshots/agents/openai.yaml`
- Test: `tests/unit/skills.test.mjs` (extend), `tests/integration/release-gates.test.mjs` (extend)

**REQUIRED SUB-SKILL:** Use superpowers:writing-skills. This is a technique skill, so it is tested with application scenarios, not pressure scenarios.

**Iron Law: no skill without a failing test first.** Do not write `SKILL.md` before running the baseline.

- [ ] **Step 1: RED, run the baseline**

Dispatch 3 fresh subagents with no skill present. Give each: a 900x560 base PNG of a card UI, the `annotate` config format, the note that `browser_run_code_unsafe` is available with a Playwright `page`, and this task: highlight the Estimate value, redact the claimant Name, and label the estimate.

Record verbatim, for each: did it measure via `boundingBox()` or estimate coordinates by reading the PNG? Did it place a label over card content? Did it draw annotations for selectors it never confirmed?

Expected baseline failure, already observed once during design: coordinates are estimated from the image, and roughly half the annotations land wrong, including a redaction that leaves the name legible.

- [ ] **Step 2: GREEN, write the skill against the observed failures**

Write `skills/annotating-screenshots/SKILL.md`. Frontmatter `description` states triggering conditions only, never the workflow. Content requirements, each traceable to a baseline failure or to the spec:

- Run `capture-annotated.js` and use its `resolved` boxes. Never estimate coordinates by reading the PNG.
- Never draw an annotation for a `missed` key. Report what was missed instead.
- The primitive vocabulary and what each is for: arrow (point at one thing), highlight (frame the value that changed), box, ellipse (ring a small badge), chip (short label), counter (steps in a flow), spotlight (isolate a region in a busy view), blur (redact PII).
- Composition rules kept from the source skill: a highlight must fully enclose its value; labels go in empty space, never over card content; never blur the value the screenshot exists to prove.
- On first use, present `OFFERED_PALETTES` and run `fast-browser configure --palette <name>` once.
- Under the default `safe` profile, `browser_run_code_unsafe` prompts for approval. Expect it; it is not a failure.
- `~/.fast-browser/screenshots/` is destroyed by `uninstall --purge-data`.

Add `agents/openai.yaml` matching the shape used by `skills/browser-macros/agents/openai.yaml`. This is not optional: all three existing skills ship one, and without it the guidance is absent on the Codex host.

- [ ] **Step 3: Verify agents now comply**

Re-run the Step 1 scenarios with the skill present. Every run must call the macro and use its returned boxes. Any run that still estimates coordinates means the wording is not binding: tighten it and re-run before proceeding.

- [ ] **Step 4: Extend the packaging tests**

```js
// append to tests/integration/release-gates.test.mjs
test('the annotation skill ships for both hosts', async () => {
  const files = await packedFiles();
  assert.ok(files.includes('skills/annotating-screenshots/SKILL.md'));
  assert.ok(files.includes('skills/annotating-screenshots/agents/openai.yaml'));
  assert.ok(files.includes('builtins/macros/capture-annotated.js'));
});

test('the vendored Radix palette carries its licence notice', async () => {
  const notices = await readFile(path.join(pluginRoot, 'THIRD_PARTY_NOTICES.md'), 'utf8');
  assert.match(notices, /Radix Colors/);
  assert.match(notices, /MIT License/);
});
```

- [ ] **Step 5: Run the full suite**

Run: `npm test`
Expected: PASS, full suite green

- [ ] **Step 6: Commit**

```bash
git add skills/annotating-screenshots tests/unit/skills.test.mjs tests/integration/release-gates.test.mjs
git commit -m "feat(fast-browser): add the annotating-screenshots skill"
```

---

### Task 12: End-to-end verification through the real runtime

**Files:**
- Create: `tests/e2e/annotate.test.mjs`

**Interfaces:**
- Consumes: everything above

This task is manual-ish and gated on a real browser, matching the existing `tests/e2e/` pattern. It is the only place the whole path is exercised.

- [ ] **Step 1: Determine where `browser_run_code_unsafe` resolves `filename`**

Before writing the test, establish this empirically; the rest of the task
depends on it and it is not documented in this repo. Start the runtime the way
`tests/e2e/direct-mcp.test.mjs` does, call `browser_run_code_unsafe` with
`filename: 'page-recon.js'`, and find which directory it read. Check the
runtime's `--output-dir` (`outputDir`) first, then `~/.fast-browser/macros/`.

Record the answer in a comment at the top of the new test. If the macro root is
the real `~/.fast-browser/macros/`, the test must copy
`builtins/macros/capture-annotated.js` there in a `before` hook and remove it
after, so the suite never depends on the developer's own install state.

- [ ] **Step 2: Write the end-to-end check**

Follows the existing harness: `startMcpClient({ outputDir })` returns an object
with `callTool(name, args)` and runs the runtime headless, so no paired Chrome
is needed. Macro results come back as text and must be JSON-parsed.

```js
// tests/e2e/annotate.test.mjs
import assert from 'node:assert/strict';
import { execFile as execFileCallback } from 'node:child_process';
import { copyFile, mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';

import { readPngSize } from '../../lib/annotate/png.mjs';
import { startMcpClient } from './helpers/mcp-client.mjs';

const execFile = promisify(execFileCallback);
const pluginRoot = fileURLToPath(new URL('../../', import.meta.url));

// A data: URL avoids standing up a fixture server for three rows of markup.
const PAGE = `data:text/html,${encodeURIComponent(`
<meta charset="utf-8">
<style>body{margin:0;font:14px Helvetica,Arial,sans-serif}
.row{display:flex;justify-content:space-between;padding:9px 20px}.v{font-weight:600}</style>
<div class="row"><span>Name</span><span class="v" id="nm">Dana Whitfield</span></div>
<div class="row"><span>Policy</span><span class="v">PA-99-4471-02</span></div>
<div class="row"><span>Estimate</span><span class="v" id="est">$4,182.60</span></div>`)}`;

async function harness(t) {
  const outputDir = await mkdtemp(path.join(os.tmpdir(), 'fb-annot-e2e-'));
  const macrosDir = path.join(outputDir, 'macros');
  await mkdir(macrosDir, { recursive: true });
  // Copy the builtin so the test never depends on the developer's install.
  await copyFile(
    path.join(pluginRoot, 'builtins/macros/capture-annotated.js'),
    path.join(macrosDir, 'capture-annotated.js'),
  );
  const client = await startMcpClient({ outputDir });
  t.after(async () => {
    await client.close?.();
    await rm(outputDir, { recursive: true, force: true });
  });
  return { client, outputDir };
}

async function measure(client, args) {
  const text = await client.callTool('browser_run_code_unsafe', {
    filename: 'capture-annotated.js',
    args,
  });
  const match = text.match(/\{[\s\S]*\}/);
  assert.ok(match, `macro returned no JSON payload: ${text}`);
  return JSON.parse(match[0]);
}

test('capture-annotated resolves, reports misses, and annotate rasterises', async (t) => {
  const { client, outputDir } = await harness(t);
  await client.callTool('browser_navigate', { url: PAGE });

  const measured = await measure(client, {
    out: 'e2e-annotate',
    targets: {
      estimate: '#est',      // exactly one match
      name: '#nm',           // exactly one match
      missing: '#not-here',  // no match
      ambiguous: '.v',       // three matches
    },
  });

  assert.equal(measured.schemaVersion, 1);
  assert.ok(measured.resolved.estimate, 'the unambiguous target resolves');
  assert.ok(measured.resolved.name, 'the redaction target resolves');
  assert.equal(measured.resolved.ambiguous, undefined, 'a multi-match never resolves');

  const reasons = Object.fromEntries(measured.missed.map((m) => [m.key, m.reason]));
  assert.equal(reasons.missing, 'no-match');
  assert.equal(reasons.ambiguous, 'ambiguous');

  const configPath = path.join(outputDir, 'e2e-annotate.json');
  await writeFile(configPath, JSON.stringify({
    base: measured.name,
    out: 'e2e-annotate-out.png',
    measured: { schemaVersion: measured.schemaVersion, viewport: measured.viewport },
    annotations: [
      { type: 'highlight', box: measured.resolved.estimate },
      { type: 'blur', box: measured.resolved.name, amount: 9 },
    ],
  }));

  const { stdout } = await execFile(
    'node',
    [path.join(pluginRoot, 'bin/fast-browser.mjs'), 'annotate', configPath, '--json'],
  );
  const report = JSON.parse(stdout);

  const base = readPngSize(await readFile(measured.png));
  const out = readPngSize(await readFile(report.out));
  assert.equal(out.width, base.width * 2);
  assert.equal(out.height, base.height * 2);
});
```

- [ ] **Step 3: Verify the redaction actually changes pixels**

A misplaced blur is the exact failure this feature exists to prevent, so assert
on pixels rather than on the command exiting zero. Rasterise the same base twice
at the same scale, once with no annotations and once with the measured blur, and
require the two rasters to differ. Comparing like-for-like rasters avoids any
scale mismatch between a 1x base and a 2x output.

```js
// append to tests/e2e/annotate.test.mjs
import { rasterise } from '../../lib/annotate/render.mjs';
import { buildSvg } from '../../lib/annotate/svg.mjs';

test('a measured blur actually changes the raster over its target', async (t) => {
  const { client, outputDir } = await harness(t);
  await client.callTool('browser_navigate', { url: PAGE });

  const measured = await measure(client, { out: 'e2e-redact', targets: { name: '#nm' } });
  const base = await readFile(measured.png);
  const { width, height } = readPngSize(base);
  const plain = path.join(outputDir, 'plain.png');
  const blurred = path.join(outputDir, 'blurred.png');

  await rasterise({
    svg: buildSvg({ base, width, height, annotations: [], palette: 'violet' }),
    outPath: plain,
  });
  await rasterise({
    svg: buildSvg({
      base,
      width,
      height,
      palette: 'violet',
      annotations: [{ type: 'blur', box: measured.resolved.name, amount: 9 }],
    }),
    outPath: blurred,
  });

  const [a, b] = await Promise.all([readFile(plain), readFile(blurred)]);
  assert.ok(a.length > 0 && b.length > 0);
  assert.ok(!a.equals(b), 'the blur must visibly change the raster');
});
```

- [ ] **Step 4: Run it**

Run: `node --test tests/e2e/annotate.test.mjs`
Expected: PASS, 2 tests. Requires `rsvg-convert` and the runtime release dir the
existing e2e suite already needs (`FAST_BROWSER_RELEASE_DIR`).

- [ ] **Step 5: Add the e2e script**

In `package.json` `scripts`, add:

```json
    "test:annotate": "node --test tests/e2e/annotate.test.mjs"
```

- [ ] **Step 6: Commit**

```bash
git add tests/e2e/annotate.test.mjs package.json
git commit -m "test(fast-browser): verify annotation end to end"
```

---

## Deferred, not in this plan

- **Session retention bug.** `runtimeArgs` passes `--output-dir=${paths.dataDir}` so the runtime writes `session-*` into `~/.fast-browser/`, but `pruneSessions` scans only `dataDir/sessions` and `dataDir/archive`. Live sessions are never pruned. Once fixed, `screenshotsDir` should be added to the same retention sweep, since annotated PNGs otherwise accumulate the same way.
- **`fullPage` annotation.** Needs its own design; scroll-offset translation misplaces fixed and sticky elements.
- **Byte-identical parity with `annotate.py`.** Explicitly abandoned; see the spec's Testing section.
