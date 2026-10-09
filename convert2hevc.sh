#!/usr/bin/env bash
# Convert every video under a directory to HEVC in Matroska, recursively.
# By Michael Gray
#
# Usage: convert2hevc.sh [--encoder NAME] [--dry-run] [--delete-originals] DIR
#
#   --encoder NAME      auto (default), nvenc, vaapi, qsv or software
#   --software          same as --encoder software (libx265 on the CPU)
#   --dry-run           list what would be converted and exit
#   --delete-originals  remove a source file after its conversion succeeds
#
# auto picks the first that works here: NVIDIA NVENC, then VAAPI (AMD and
# Intel), then Intel Quick Sync, then libx265.
#
# Environment:
#   VAAPI_DEVICE  render node for VAAPI and QSV (default /dev/dri/renderD128)
#   QUALITY       constant-quality value; lower is better and larger
#                 (defaults: nvenc 24, vaapi 20, qsv 24, software 22)
#
# Output is "<name> - HEVC.mkv" beside the source. Audio is copied as-is
# rather than re-encoded: the old version forced 6-channel Vorbis, which
# upmixed stereo sources to a fake 5.1 and lost quality on every pass.
set -euo pipefail

usage() { sed -n '4,20p' "$0" | sed 's/^# \{0,1\}//'; }

encoder=auto
dry_run=0
delete_originals=0
while [ $# -gt 0 ]; do
    case "$1" in
        --software) encoder=software ;;
        --encoder)
            [ $# -ge 2 ] || { echo "--encoder needs a value" >&2; exit 2; }
            encoder=$2; shift ;;
        --encoder=*) encoder=${1#--encoder=} ;;
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
ffmpeg_encoders=$(ffmpeg -hide_banner -encoders 2>/dev/null || true)
has_encoder() { grep -q " $1 " <<<"$ffmpeg_encoders"; }

# Whether an encoder can run on this machine, not just whether ffmpeg was
# built with it: a build lists hevc_nvenc even with no NVIDIA card present.
usable() {
    case "$1" in
        nvenc) has_encoder hevc_nvenc && command -v nvidia-smi >/dev/null && nvidia-smi -L >/dev/null 2>&1 ;;
        vaapi) has_encoder hevc_vaapi && [ -e "$vaapi_device" ] ;;
        qsv) has_encoder hevc_qsv && [ -e "$vaapi_device" ] ;;
        software) has_encoder libx265 ;;
        *) return 1 ;;
    esac
}

case "$encoder" in
    auto)
        for candidate in nvenc vaapi qsv software; do
            if usable "$candidate"; then encoder=$candidate; break; fi
        done
        if [ "$encoder" = auto ]; then
            echo "No usable HEVC encoder: this ffmpeg has no libx265 and no working hardware encoder" >&2
            exit 1
        fi
        echo "encoder: $encoder"
        ;;
    nvenc|vaapi|qsv|software)
        if [ "$dry_run" = 0 ] && ! usable "$encoder"; then
            echo "Encoder '$encoder' is not usable here (missing from ffmpeg, or no device; VAAPI_DEVICE=$vaapi_device)" >&2
            exit 1
        fi
        ;;
    *) echo "Unknown encoder: $encoder (use auto, nvenc, vaapi, qsv or software)" >&2; exit 2 ;;
esac

case "$encoder" in
    nvenc)
        video_args=(-c:v hevc_nvenc -preset p5 -rc vbr -cq "${QUALITY:-24}" -b:v 0) ;;
    vaapi)
        video_args=(-vaapi_device "$vaapi_device" -vf 'format=nv12|vaapi,hwupload'
                    -c:v hevc_vaapi -qp:v "${QUALITY:-20}") ;;
    qsv)
        video_args=(-init_hw_device "qsv=hw:$vaapi_device" -filter_hw_device hw
                    -vf 'format=nv12,hwupload=extra_hw_frames=64'
                    -c:v hevc_qsv -global_quality "${QUALITY:-24}") ;;
    software)
        video_args=(-c:v libx265 -crf "${QUALITY:-22}" -preset medium
                    -x265-params log-level=error) ;;
esac

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
