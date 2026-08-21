# design-sync notes — Seamly

## Do not run the converter path against this repo

`design-system/` is **hand-authored**, not a component library with a build:

- no `package.json`, no lockfile, no `dist/`, no Storybook, no `*.stories.*`
- JSX sources in `design-system/src/`, bundled to a **committed** `_ds_bundle.js`
  (the esbuild command is in `design-system/readme.md` under "Building")
- guideline and component cards are hand-written `*.card.html` files whose first
  line carries an `@dsCard` marker

The skill's converter entry (`package-build.mjs`) begins with "faithful install
with the repo's own package manager". There is nothing to install, so that path
cannot run as designed. Producing the layout by other means is what §2 permits.

## The claude.ai/design project is managed by a DIFFERENT tool

Project `f9e8831d-2cc1-4513-9cf0-aea67fd27259` ("Seamly.app") was produced by
**`design-sync-cli`** — its manifest says `"source": "design-sync-cli"`. It has
`_ds_manifest.json` and **no `_ds_sync.json`**, which is this skill's anchor.

**`.design-sync/config.json` is deliberately absent.** Pinning that `projectId`
would route a future run down the atomic path, which reconciles the remote to
this skill's layout (`components/<group>/<Name>/…` + `_ds_sync.json`) and could
delete or restructure a working design system built by another tool. An unpinned
run creates a duplicate project instead — visible and recoverable. If you ever
do want this repo skill-managed, that is a deliberate migration, not a re-sync.

## How to get a new card indexed

The pane reads `_ds_manifest.json`, which the app recompiles from the `@dsCard`
markers when `_ds_needs_recompile` is present and the project is opened.

- `register_assets` reported `registered: 1` but left `_ds_manifest.json`
  unchanged — it does **not** index cards in this project. Don't rely on it.
- Uploading a `.card.html` alone does nothing; it is not in the index.
- What worked: upload the card, then upload `_ds_needs_recompile` (it was missing
  from the remote entirely), then **open the project** to trigger the recompile.

## Housekeeping

- "Published" is unchecked on the project — it is not yet available to the team.
- The "missing brand fonts" warning is by design: `readme.md` states "No
  webfonts. SF Pro is the real typeface and ships with the platform."

## Bundle drift — found and fixed 2026-08-22

`_ds_bundle.js` had gone **stale** against `src/`: it was committed in
"add Seamly.app design system source" (Aug 19 23:36) but `src/` was last changed
18 minutes later in "fix contrast failures" (23:54). `_ds_needs_recompile` was
set to `1` and had been for two days. The remote project served the old bundle,
so the click-through UI kit rendered pre-fix code.

The drift was **caused by the build docs.** `readme.md`'s command omitted the
`window.SeamlyPaper` alias, which esbuild's `--global-name` does not emit — the
line `window.SeamlyPaper=SeamlyApp_f9e883;` is appended by a footer. Anyone
rebuilding per the docs silently dropped the alias, so the safe move was not to
rebuild, and the bundle rotted instead.

Fixed by adding `--footer:js='window.SeamlyPaper=SeamlyApp_f9e883;'` to the
documented command, which is now **verified reproducible**: running the readme's
command verbatim produces the committed `_ds_bundle.js` byte-for-byte. Re-check
that property after any change to the build line.

`ui_kits/seamly-ios/README.md` also claimed "Every screen is built from
`window.SeamlyPaper`". The code actually resolves
`SeamlyKit || SeamlyApp_f9e883 || SeamlyPaper`, which is the only reason the kit
kept working while the alias was missing from fresh builds. Corrected.

### Checked and NOT broken (don't re-investigate)

- `--s-2/-3/-4/-5/-7/-8/-10` look undefined to a line-anchored grep because
  `tokens/layout.css` defines them several per line. They are defined.
- Dynamic `var(--mark-${tone})` / `var(--wash-${tone})` in `IconButton` and
  `StatusNote` resolve for every tone in their contracts (`ink|flag|gap|error`
  and `ok|flag|gap|error`).
- `--mark-rec` has no `--wash-rec`. Intentional — nothing pairs them.
