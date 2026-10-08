#!/usr/bin/env bash
# Convert every video under a directory to HEVC in Matroska, recursively.
# By Michael Gray
#
# Usage: convert2hevc.sh [--software] [--dry-run] [--delete-originals] DIR
#
#   --software          encode with libx265 on the CPU instead of VAAPI
#   --dry-run           list what would be converted and exit
#   --delete-originals  remove a source file after its conversion succeeds
#
# Environment:
#   VAAPI_DEVICE  render node for VAAPI (default /dev/dri/renderD128)
#   QUALITY       VAAPI -qp / libx265 -crf value (default 20 / 22)
#
# Output is "<name> - HEVC.mkv" beside the source. Audio is copied as-is
# rather than re-encoded: the old version forced 6-channel Vorbis, which
# upmixed stereo sources to a fake 5.1 and lost quality on every pass.
set -euo pipefail

usage() { sed -n '4,13p' "$0" | sed 's/^# \{0,1\}//'; }

encoder=vaapi
dry_run=0
delete_originals=0
while [ $# -gt 0 ]; do
    case "$1" in
        --software) encoder=software ;;
        --dry-run) dry_run=1 ;;
        --delete-originals) delete_originals=1 ;;
        -h|--help) usage; exit 0 ;;
        --) shift; break ;;
        -*) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
        *) break ;;
    esac
    shift
done

if [ $# -ne 1 ] || [ ! -d "$1" ]; then
    usage >&2
    exit 2
fi
target=$1

command -v ffmpeg >/dev/null || { echo "ffmpeg is not installed" >&2; exit 1; }

vaapi_device=${VAAPI_DEVICE:-/dev/dri/renderD128}
if [ "$encoder" = vaapi ]; then
    if [ "$dry_run" = 0 ] && [ ! -e "$vaapi_device" ]; then
        echo "VAAPI device $vaapi_device not found; set VAAPI_DEVICE or use --software" >&2
        exit 1
    fi
    video_args=(-vaapi_device "$vaapi_device" -vf 'format=nv12|vaapi,hwupload'
                -c:v hevc_vaapi -qp:v "${QUALITY:-20}")
else
    video_args=(-c:v libx265 -crf "${QUALITY:-22}" -preset medium
                -x265-params log-level=error)
fi

converted=0
skipped=0
failed=0

# -print0 / read -d '' so names with spaces, quotes or newlines survive.
while IFS= read -r -d '' src; do
    out="${src%.*} - HEVC.mkv"
    if [ -e "$out" ]; then
        echo "skip (already converted): $src"
        skipped=$((skipped + 1))
        continue
    fi
    if [ "$dry_run" = 1 ]; then
        echo "would convert: $src"
        continue
    fi

    # Matroska can carry MKV subtitles as-is; MP4 text subtitles cannot be
    # copied into it, so other containers keep video and audio only.
    sub_args=()
    case "${src,,}" in
        *.mkv) sub_args=(-map '0:s?' -c:s copy) ;;
    esac

    # Encode to a temporary name and rename on success, so an interrupted
    # run never leaves a partial file that the next run would skip as done.
    tmp="${out%.mkv}.partial.mkv"
    echo "convert: $src"
    if nice -n 15 ffmpeg -hide_banner -loglevel error -nostdin -y \
            -i "$src" -map 0:v:0 -map '0:a?' "${sub_args[@]}" \
            "${video_args[@]}" -c:a copy -f matroska "$tmp"; then
        mv -- "$tmp" "$out"
        converted=$((converted + 1))
        if [ "$delete_originals" = 1 ]; then
            rm -- "$src"
        fi
    else
        rm -f -- "$tmp"
        echo "FAILED: $src" >&2
        failed=$((failed + 1))
    fi
done < <(find "$target" -type f \
            \( -iname '*.mkv' -o -iname '*.mp4' -o -iname '*.m4v' -o -iname '*.mov' \
               -o -iname '*.avi' -o -iname '*.mpg' -o -iname '*.mpeg' -o -iname '*.wmv' \) \
            -not -iname '* - HEVC.mkv' -not -iname '*.partial.mkv' -print0)

echo "converted $converted, skipped $skipped, failed $failed"
[ "$failed" -eq 0 ]
