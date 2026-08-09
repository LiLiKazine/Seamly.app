#!/usr/bin/env bash
#
# Download the binary test fixtures, which are hosted as GitHub Release assets rather than
# committed. Everything about a fixture *except* its pixels — the READMEs carrying ground truth,
# and `manifest.json` — is in the repo; this script fetches the pixels.
#
#   scripts/fetch-fixtures.sh              # fetch every set that is missing or stale
#   scripts/fetch-fixtures.sh Screenshots3 # fetch just one set
#   scripts/fetch-fixtures.sh --check      # verify only, download nothing (exit 1 if incomplete)
#   scripts/fetch-fixtures.sh --force      # re-download even if present
#
# Idempotent: a set whose marker matches the manifest's sha256 is skipped, so running it before
# every test loop costs one `test -f`.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
manifest="$repo_root/Seamly/StitchKit/Tests/StitchKitTests/Fixtures/manifest.json"

[[ -f "$manifest" ]] || { echo "error: no manifest at $manifest" >&2; exit 1; }

# `python3` is present on every macOS since 12 and is already required by the repo's tooling; it
# reads the manifest so the script does not hand-parse JSON.
field() { python3 -c "import json,sys;d=json.load(open('$manifest'));print(d[sys.argv[1]])" "$1"; }
sets_tsv() {
  python3 -c "
import json
d = json.load(open('$manifest'))
for s in d['sets']:
    print('\t'.join([s['name'], s['asset'], s['sha256'], str(s['bytes'])]))
"
}

# Do the files already on disk match the manifest byte for byte? Used to *adopt* a fixture tree
# that arrived some other way — a checkout from before the fixtures moved out of the repo, or a
# hand-copied set — instead of re-downloading it. Verifying content, not just presence, is the
# point: this is what makes "the pixels on disk are the pixels the ground truth was measured from"
# a checkable claim rather than an assumption.
set_matches_on_disk() {
  python3 - "$manifest" "$root" "$1" <<'PY'
import hashlib, json, os, sys
manifest, root, name = sys.argv[1], sys.argv[2], sys.argv[3]
spec = next((s for s in json.load(open(manifest))['sets'] if s['name'] == name), None)
if spec is None:
    sys.exit(1)
for entry in spec['files']:
    path = os.path.join(root, name, entry['name'])
    if not os.path.exists(path) or os.path.getsize(path) != entry['bytes']:
        sys.exit(1)
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    if h.hexdigest() != entry['sha256']:
        sys.exit(1)
sys.exit(0)
PY
}

gh_repo="$(field repo)"
release="$(field release)"
root="$repo_root/$(field root)"

check_only=0
force=0
wanted=()
for arg in "$@"; do
  case "$arg" in
    --check) check_only=1 ;;
    --force) force=1 ;;
    -h|--help) sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "error: unknown flag $arg" >&2; exit 2 ;;
    *) wanted+=("$arg") ;;
  esac
done

missing=0
fetched=0

while IFS=$'\t' read -r name asset sha bytes; do
  if [[ ${#wanted[@]} -gt 0 ]] && ! printf '%s\n' "${wanted[@]}" | grep -qx "$name"; then
    continue
  fi

  dest="$root/$name"
  # The marker records which manifest revision produced the files on disk, so a fixture set that
  # is re-cut upstream is re-fetched rather than silently kept. It is deliberately inside the
  # (gitignored) fixture directory and never committed.
  marker="$dest/.fixture-sha256"

  if [[ $force -eq 0 && -f "$marker" ]] && [[ "$(cat "$marker")" == "$sha" ]]; then
    continue
  fi

  # No marker, but the files may already be here and correct. Adopt them rather than re-download.
  if [[ $force -eq 0 ]] && set_matches_on_disk "$name"; then
    echo "$sha" > "$marker"
    continue
  fi

  if [[ $check_only -eq 1 ]]; then
    echo "missing or stale: $name"
    missing=$((missing + 1))
    continue
  fi

  url="https://github.com/$gh_repo/releases/download/$release/$asset"
  tmp="$(mktemp -t "$asset.XXXXXX")"
  trap 'rm -f "$tmp"' EXIT

  printf 'fetching %-14s %6.1f MB ... ' "$name" "$(echo "$bytes" | awk '{print $1/1048576}')"
  if ! curl -fsSL --retry 3 --retry-delay 2 -o "$tmp" "$url"; then
    echo "FAILED"
    echo "error: could not download $url" >&2
    echo "       if the release is private, run: gh release download $release --repo $gh_repo --pattern '$asset'" >&2
    rm -f "$tmp"
    exit 1
  fi

  actual="$(shasum -a 256 "$tmp" | cut -d' ' -f1)"
  if [[ "$actual" != "$sha" ]]; then
    echo "FAILED"
    echo "error: checksum mismatch for $asset" >&2
    echo "       expected $sha" >&2
    echo "       actual   $actual" >&2
    rm -f "$tmp"
    exit 1
  fi

  # Tarball members are stored as `<SetName>/<file>`, relative to the Fixtures directory.
  mkdir -p "$root"
  tar -xzf "$tmp" -C "$root"
  echo "$sha" > "$marker"
  rm -f "$tmp"
  trap - EXIT
  echo "ok"
  fetched=$((fetched + 1))
done < <(sets_tsv)

if [[ $check_only -eq 1 ]]; then
  if [[ $missing -gt 0 ]]; then
    echo "" >&2
    echo "$missing fixture set(s) missing. Run: scripts/fetch-fixtures.sh" >&2
    exit 1
  fi
  echo "all fixture sets present and current"
  exit 0
fi

if [[ $fetched -eq 0 ]]; then
  echo "all fixture sets already present and current"
else
  echo "fetched $fetched set(s)"
fi
