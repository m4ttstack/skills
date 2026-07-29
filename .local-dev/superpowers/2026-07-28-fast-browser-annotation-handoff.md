# Fast Browser screenshot annotation: handoff

Branch: `fast-browser-dual-host`. Feature range: `6853a8f..bc3079b`, 25 commits.
Plan: `.local-dev/superpowers/plans/2026-07-28-fast-browser-annotation.md`.
Full audit trail: `.superpowers/sdd/2026-07-28-fast-browser-annotation/`
(`progress.md` is the ledger, `deferred-findings.md` is the catalogue).

**Status: all 12 tasks complete, final whole-branch review clean, merge-ready.**
`npm test` 503/503, `node --test tests/e2e/annotate.test.mjs` 2/2 against the
real runtime and real `rsvg-convert`.

Nothing below blocks merge. These are the things I could not decide for you.

---

## Decision 1: `setup`'s reinstall path silently resets two more config fields

This is the one I would act on first, because one of them is a privacy
regression.

`lib/commands/setup.mjs` rebuilds config on the reinstall branch from
`defaultConfig()` plus a fixed set of carried fields. The final review caught
that `annotation.palette` was dropped there, and that is now fixed (`bc3079b`).
Applying that fix surfaced two more fields with the identical defect, which I
verified directly but did not fix:

**(a) `sessions` is reset to `profileDefaults(profile)` unconditionally.**
`setup.mjs:385` computes `const defaults = profileDefaults(profile)` and
`:400` passes `sessions: defaults`. When the reinstall branch is entered for a
reason *other* than a profile change (a host-set change like `setup --host both`,
or a drift repair), a user who ran `configure --no-record-sessions
--retention-days 90` gets **session recording silently re-enabled** and
retention reset to 30.

That is verbatim the scenario this plan's own Task 6 fixed for `configure`
(commit `fb84fdd`, "keep configure from resetting sessions on unrelated
changes"), surviving on a second code path. The correct fix mirrors Task 6
exactly:

```js
const sessionFallback = profileChanged ? defaults : current.sessions;
```

Resetting to profile defaults on a genuine profile change is arguably correct,
which is why this needs your judgement rather than a mechanical carry. Only the
unchanged-profile entries are wrong.

**(b) `connection` resets to `manual`**, silently dropping auto-connect
(`lib/runtime/launch.mjs:120`) while the Keychain token remains. `doctor` does
not catch it: the `pairing` check passes when mode is not `auto`. Quiet but
recoverable.

`productVersion` is latent only (`defaultConfig` is its sole writer today);
`schemaVersion` is fine.

**Why I did not fix these.** I verified with `git log` that `sessions: defaults`
predates this plan entirely: `setup.mjs` was last touched before `6853a8f` by
`d64a1bc`, and only `ec791fc` and `bc3079b` touched it during this plan. So it
is a pre-existing defect this work uncovered, not one it caused, and repairing
pre-existing config-reset behaviour in `setup` is scope expansion you should
authorise.

The final reviewer independently reached the same underlying question and
phrased it well: **which config fields is each lifecycle path allowed to
rewrite?** Today the answer is implicit and differs per branch, which is why the
same class of bug has now appeared three times. A single explicit carry-list
would close it structurally instead of one field at a time.

---

## Decision 2: built-in macro fixes cannot reach an existing install

`lib/macros/install.mjs` uses `copyWithoutOverwrite`, which returns false on
`EEXIST` and never refreshes, and `ensureLiveIndex` only appends *missing*
`## <name>` sections and never updates an existing one. So a machine that
installed before a built-in macro fix keeps the broken macro and the stale index
entry permanently, and re-running `setup` repairs neither.

This conflicts directly with the plan's Task 9 mandate to keep
`copyWithoutOverwrite` so "a user-edited macro is NEVER overwritten". That
mandate is exactly what makes a shipped built-in bug permanent.

Found independently by a fix re-reviewer and by a live verification run, then
reproduced by me: after the macro fix landed, the local install still held the
broken macro *and* a stale `Params` line missing the new required `home` arg.

**Practical impact today is nil.** `capture-annotated.js` is new on this branch
and has never shipped, so no released install can hold the broken copy. The only
affected machine was yours, because I installed it during verification, and I
have refreshed both your local macro and your local `MACROS.md` by hand.

Options, roughly in increasing cost: accept it and rely on macros being right
before first release; checksum-based refresh that replaces a built-in only when
its bytes match a previously shipped version (preserving genuine user edits); or
a `doctor` macro-drift check that tells the user to reinstall. The middle option
is the one that actually solves it.

Worth deciding before the next built-in macro change, not urgently.

---

## Worth a look, lower stakes

**The tilde trap is still latent for `page-recon`.** The final fix wave
corrected `skills/annotating-screenshots/SKILL.md` to document the macro's
absolute path, because `browser_run_code_unsafe` resolves a relative `filename`
against the Playwright server's CWD (not the macros directory) and additionally
enforces containment roots, so a bare name fails with `ENOENT`. But
`skills/browser-macros/SKILL.md:13-14` still tells agents to pass "the entry's
`filename`", and the index's `Script:` values carry a literal `~`. Same defect
class, different macro. The final review scoped only the annotation skill, so
this was correctly left out of the fix wave.

`skills/browser-macros/MACROS.md` also keeps the older "no Node globals"
phrasing that the fix wave softened in the macro comment (`console` is in fact
present). Same operative claim, less precise wording.

**Deferred findings.** `deferred-findings.md` catalogues 27 Minors and 2 parked
findings that the final review explicitly triaged as ship-as-is. They are real
but individually small, and the reasoning per item is recorded there.

---

## Two things about this run worth knowing

**A Critical defect shipped through 486 passing tests.** The
`capture-annotated.js` macro read `process.env.HOME`, which throws
`ReferenceError: process is not defined` because `browser_run_code_unsafe` runs
with no Node globals. Every macro unit test called the function directly in Node,
where `process` exists, so the whole suite was blind to it. It was found only by
running the macro live. The durable fix is the regression guard that now runs the
macro in a bare `vm.createContext({})`, which reproduces the real sandbox and
would catch any reintroduced Node global. Worth remembering as a pattern: this
repo has code that executes in a realm its tests do not reproduce.

**The plan's predicted RED baseline for the skill did not reproduce.** The plan
expected unskilled agents to eyeball coordinates off the PNG and land roughly
half the annotations wrong. All three baseline samples measured properly via
`getBoundingClientRect()` and landed correctly. The real failures were subtler:
two of three paired a PNG with measurements from a *different page load*, one
fabricated the `measured` corroboration block by hand, and all three padded
measured boxes by feel. I had the skill written against what was actually
observed rather than the prediction, and both GREEN verification runs then
complied on every one of those points. If you would rather it had been written
against the plan as literally specified, that is a reasonable thing to disagree
with, and the baseline transcripts are summarised in the ledger.
