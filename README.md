# Convert Videos To HEVC

Finds every video under a directory and converts it to HEVC in a Matroska
file named `<name> - HEVC.mkv` beside the original. By default it uses
hardware encoding through VAAPI (AMD and Intel open-source drivers on Linux);
`--software` uses libx265 on the CPU instead.

```bash
./convert2hevc.sh --dry-run ~/Videos           # list what would be converted
./convert2hevc.sh ~/Videos                     # VAAPI
./convert2hevc.sh --software ~/Videos          # libx265
./convert2hevc.sh --delete-originals ~/Videos  # remove each source after it succeeds
```

- Audio is copied unchanged. Subtitles are kept for `.mkv` sources.
- Files that already have a `- HEVC.mkv` beside them are skipped, so a run
  can be stopped and restarted. Each file is written under a temporary name
  and renamed only when ffmpeg succeeds.
- `VAAPI_DEVICE` picks the render node (default `/dev/dri/renderD128`) and
  `QUALITY` sets VAAPI `-qp` (default 20) or libx265 `-crf` (default 22).
- The exit status is non-zero if any file failed.

Even with hardware encoding, a large library takes a long time.
