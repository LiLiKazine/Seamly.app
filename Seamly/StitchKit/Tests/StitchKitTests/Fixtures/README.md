# Fixtures

Real captures — screenshots and screen recordings at native device resolution — that the stitching
core is tested against. `CLAUDE.md` puts it plainly: *a green synthetic suite is necessary but not
sufficient*, and a green suite here has lied three times. These are the pixels that catch what the
synthetic ones cannot.

## The pixels are not in the repo

Binary fixtures are hosted as assets on the [`fixtures-v1`][release] GitHub Release. Fetch them
once per clone:

```bash
scripts/fetch-fixtures.sh            # everything missing or stale
scripts/fetch-fixtures.sh Screenshots3   # one set
scripts/fetch-fixtures.sh --check    # verify only; exit 1 if incomplete
```

The script verifies every file's SHA-256 against `manifest.json` before writing it, and will
*adopt* a tree that is already correct rather than re-download it — so running it before a test
loop costs about a second.

What stays **in** the repo, deliberately:

| kept | why |
|------|-----|
| every set's `README.md` | the ground truth — measured offsets, chrome bands, why the set exists. It is the part worth reading before you measure anything, and it must survive the pixels being absent. |
| `manifest.json` | per-set and per-file SHA-256 and byte counts. Makes "the pixels on disk are the pixels the ground truth was measured from" a checkable claim. |
| `wikipedia.png` | `Package.swift` declares it as a single-file resource, and SwiftPM fails the **build** — not the test — when a declared resource path is missing. A build error here would be far more confusing than a missing-fixture test failure. |

## A missing fixture fails; it never skips

`FixturePresenceTests` is the single actionable failure for an unfetched checkout — it names the
command to run, instead of leaving you to decode a scatter of `missing fixture IMG_1863` errors
across a dozen unrelated suites.

**Do not add `withKnownIssue`, a `skip`, or an early return to it.** A real-pixel test that quietly
turns into a no-op is exactly the failure mode this project has already been bitten by three times,
wearing a new costume.

## Adding or changing a set

1. Put the files in `Fixtures/<SetName>/`.
2. Write `<SetName>/README.md`: resolution, scroll order, ground truth measured **on the raw
   pixels** (not through `VerticalProfile` — it is the independent yardstick), and why the set is
   kept. If you have not measured something, say so rather than inventing it.
3. Re-cut the tarball and update `manifest.json`:

   ```bash
   cd Seamly/StitchKit/Tests/StitchKitTests/Fixtures
   tar -czf /tmp/<SetName>.tar.gz $(find <SetName> -type f ! -name README.md ! -name .DS_Store | sort)
   # then update manifest.json's sha256/bytes/files for that set
   GH_CONFIG_DIR=~/.config/gh-lilikazine gh release upload fixtures-v1 \
       /tmp/<SetName>.tar.gz --repo LiLiKazine/Seamly.app --clobber
   ```

`FixturePresenceTests` fails if a set exists on disk but not in `manifest.json` — otherwise it
would work on your machine and be absent from every fresh clone.

**When measuring, check your yardstick's own floor.** The oracle written to validate
`Screenshots4` carried a minimum-overlap cutoff and reported the best offset *below its own floor*
— 2142 px against a true 2159 px, the same class of bug it had been written to catch. See
`docs/logs/2026-08-09-03-geometric-overlap-floor.md`.

[release]: https://github.com/LiLiKazine/Seamly.app/releases/tag/fixtures-v1
