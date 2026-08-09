# 2026-08-10-01: Binary fixtures moved out of the repository

**Status:** Implemented

## Context

The fixture tree had reached **~105 MB** across 46 files — real screenshots and screen recordings
at native 1320×2868 — and `.git` was **110 MB**, essentially all of it fixtures. Each new capture
set adds another 10–25 MB, and `docs/logs/2026-08-09-03` had just added four sets at once.

The project's testing culture makes shrinking by downsampling a non-option: `CLAUDE.md` requires
fixtures at full resolution, because a different downsample changes `rowScale` and therefore what
the matcher does. The pixels have to stay exactly as they are; the only question is where they live.

## Options

| Approach | Pros | Cons |
|----------|------|------|
| Do nothing | Zero friction; `swift test` needs no network or setup | 110 MB clone, growing ~10–25 MB per capture set |
| Git LFS, track forward only | Standard, transparent checkout | Doesn't shrink `.git` at all — old blobs stay in history; **and** GitHub meters LFS bandwidth at 1 GiB/month, which ~9 full clones would exhaust |
| Git LFS + `lfs migrate import` | Shrinks the packfile | Same metered bandwidth, on every clone and CI run, forever |
| Fixtures in a submodule | Familiar; pinned by SHA | Relocates the weight rather than removing it — the submodule is still a git repo full of binary blobs — plus `--recurse-submodules` footguns |
| S3 / Cloudflare R2 | Cheap egress | Needs credentials and a bill for a public repo that needs neither |
| **GitHub Release assets (chosen)** | **Not bandwidth-metered**; free; same host and auth; public repo means `curl` needs no token | Adds a fetch step to a previously zero-setup test loop |

The deciding factor was bandwidth. LFS was the obvious first answer and was rejected specifically
because its 1 GiB/month ceiling turns routine cloning into a quota problem, while Release assets
have no such meter.

## Decision

Binary fixtures are hosted as one tarball per set on the `fixtures-v1` GitHub Release, fetched by
`scripts/fetch-fixtures.sh`. Everything *about* a fixture stays in the repo — each set's
`README.md` (its ground truth) and `manifest.json` (per-set and per-file SHA-256).

History was then rewritten with `git filter-repo` to purge the blobs, and every ref force-pushed.

## Rationale

Two constraints shaped the design more than the hosting choice did.

**A missing fixture must fail, never skip.** This repo has been bitten three times by a green suite
that wasn't exercising what it claimed. A real-pixel test that silently becomes a no-op because its
pixels are absent is that same failure in a new costume. So `FixturePresenceTests` exists as the
single actionable failure, naming the command to run, and `CLAUDE.md` forbids adding `withKnownIssue`
or an early return to it.

**The ground truth is the valuable part.** The measured offsets, chrome bands, and *why the set is
kept* are what make a fixture usable; the pixels are replaceable bytes. So the READMEs stay in the
repo and must survive the pixels being absent, which `everyFixtureSetKeepsItsGroundTruthInTheRepo`
enforces.

`wikipedia.png` is deliberately exempt and still committed: `Package.swift` declares it as a
single-file resource, and SwiftPM fails the whole **build** when a declared resource path is
missing. A build error is a far worse first experience than a clear missing-fixture test failure.
Directories are safe because their `README.md` keeps them existing.

## What Changed

- `scripts/fetch-fixtures.sh` — fetch / `--check` / `--force` / per-set; verifies SHA-256 before
  writing; *adopts* an already-correct tree instead of re-downloading (~1 s vs ~47 s).
- `Fixtures/manifest.json` — per-set and per-file SHA-256 and byte counts.
- `Fixtures/README.md` — the scheme; `Fixtures/Example/README.md` — the one set that had none.
- `FixturePresenceTests` — presence, size, manifest/disk agreement, README survival.
- `.gitignore`, `CLAUDE.md`, and 46 files untracked.
- History rewritten; `main` and both feature branches force-pushed; the `fixtures-v1` tag moved.

## Results

| | before | after |
|---|--------|-------|
| `.git` | 110 MB | **3.0 MB** |
| fresh clone | ~110 MB | **3.0 MB in 1.8 s** |
| fixture blobs reachable from any ref | 46 | **0** |

Verified rather than assumed: wiped all local fixtures (presence test failed with the fetch
command), fetched 105 MB from the release, byte-compared every file against the originals (**0
differences of 53**), ran the full suite (151 tests, 2 known issues), then cloned fresh and ran the
real-pixel suites there.

## What Was Discovered

- **The repo used to be called Longshot, and the first rewrite missed it.** Filtering on
  `Seamly/StitchKit/…` left 16 files / 27 MB behind under `Longshot/StitchKit/…`, so `.git` stopped
  at 30 MB instead of 3 MB. A path filter has to match every name a directory has ever had. The fix
  was to key on the `StitchKit/Tests/StitchKitTests/Fixtures/` infix rather than a repo-root prefix.
- **Rewriting `main` is not enough.** Two merged-but-undeleted feature branches and the release
  **tag** still pointed at pre-rewrite commits, each keeping the whole old object graph alive. Every
  ref has to move, tags included.
- **`git check-ignore` skips paths that are in the index**, so it reports nothing for tracked files
  and reads as "my patterns don't match". Verifying ignore rules for files you are about to untrack
  needs `--no-index`.
- **`git tag -f <name> <sha>` fails with "no tag message?" when `tag.gpgsign` is set** — it tries to
  annotate. Needs an explicit `-a -m`.
- **GitHub's reported repository size does not drop.** It still reads 110 MB because unreachable
  objects are only reclaimed by GitHub's own gc. A fresh clone is already 3 MB, so this is cosmetic;
  contact GitHub Support if the number itself matters.
- **The presence test's first version failed with a `DecodingError`**, not a useful message, because
  the manifest gained per-file hashes while the Swift model still expected `[String]`. It failed
  loudly rather than passing vacuously — the right direction — but a manifest schema and its reader
  have to move together.

## Follow-ups

- The fast primary loop is no longer zero-setup: a fresh checkout needs `scripts/fetch-fixtures.sh`
  before `swift test`. If CI is ever added, that step must come before the test job, or the run will
  fail in `FixturePresenceTests` — which is the intended, legible failure.
- A backup bundle of the pre-rewrite history is at
  `~/Developer/seamly-backup-2026-08-09/seamly-all-refs.bundle` (113 MB, `git bundle verify` clean).
  Delete it once the rewrite is known good.
