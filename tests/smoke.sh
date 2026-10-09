#!/usr/bin/env bash
# End-to-end check on generated clips, CPU encoder only (CI has no GPU).
# Covers the behaviour that would lose or damage a library if it regressed:
# odd filenames, skip-if-done, audio copied rather than upmixed, and
# originals deleted only on request.
set -euo pipefail

script="$(cd "$(dirname "$0")/.." && pwd)/convert2hevc.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/sub dir"

ffmpeg -loglevel error -f lavfi -i testsrc=d=1:s=160x120 -f lavfi -i sine=d=1 \
    -ac 2 -shortest "$work/sub dir/it's a clip.mp4"
ffmpeg -loglevel error -f lavfi -i testsrc=d=1:s=160x120 "$work/plain.mkv"

fail() { echo "FAIL: $*" >&2; exit 1; }

out=$("$script" --dry-run "$work")
[ "$(grep -c '^would convert' <<<"$out")" = 2 ] || fail "dry run should list 2 files: $out"
[ -z "$(find "$work" -name '* - HEVC.mkv')" ] || fail "dry run wrote output"

"$script" --encoder software "$work" >/dev/null
converted="$work/sub dir/it's a clip - HEVC.mkv"
[ -f "$converted" ] || fail "missing $converted"
[ "$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$converted")" = hevc ] \
    || fail "video is not HEVC"
[ "$(ffprobe -v error -select_streams a:0 -show_entries stream=channels -of csv=p=0 "$converted")" = 2 ] \
    || fail "stereo audio was not kept as stereo"
[ -z "$(find "$work" -name '*.partial.mkv')" ] || fail "temporary file left behind"

out=$("$script" --software "$work")
grep -q 'converted 0, skipped 2, failed 0' <<<"$out" || fail "second run should skip both: $out"
[ -f "$work/plain.mkv" ] || fail "original deleted without --delete-originals"

rm "$work/plain - HEVC.mkv"
"$script" --software --delete-originals "$work" >/dev/null
[ ! -f "$work/plain.mkv" ] || fail "--delete-originals kept the source"
[ -f "$work/sub dir/it's a clip.mp4" ] || fail "--delete-originals removed a file it skipped"

if "$script" --encoder bogus "$work" >/dev/null 2>&1; then fail "unknown encoder accepted"; fi

echo "smoke: all checks passed"
