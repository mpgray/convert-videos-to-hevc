# Convert Videos To HEVC

Finds every video under a directory and converts it to HEVC in a Matroska
file named `<name> - HEVC.mkv` beside the original. It uses your GPU when it
can and falls back to libx265 on the CPU when it can't.

```bash
./convert2hevc.sh --dry-run ~/Videos           # list what would be converted
./convert2hevc.sh ~/Videos                     # pick the best encoder available
./convert2hevc.sh --encoder vaapi ~/Videos     # force one: nvenc, vaapi, qsv, software
./convert2hevc.sh --delete-originals ~/Videos  # remove each source after it succeeds
```

## Encoders

With the default `--encoder auto`, the script uses the first one that works
on this machine and prints which it chose:

| Encoder | Hardware | Quality default (`QUALITY`) |
|---|---|---|
| `nvenc` | NVIDIA GPU (needs `nvidia-smi`) | `-cq 24` |
| `vaapi` | AMD or Intel on Linux, via the open-source drivers | `-qp 20` |
| `qsv` | Intel Quick Sync | `-global_quality 24` |
| `software` | Any CPU (libx265) | `-crf 22` |

Lower `QUALITY` means better quality and larger files. `VAAPI_DEVICE` picks
the render node for VAAPI and QSV (default `/dev/dri/renderD128`).
`--software` is shorthand for `--encoder software`.

## Behaviour

- Audio is copied unchanged. Subtitles are kept for `.mkv` sources.
- Files that already have a `- HEVC.mkv` beside them are skipped, so a run
  can be stopped and restarted. Each file is written under a temporary name
  and renamed only when ffmpeg succeeds.
- The exit status is non-zero if any file failed.

Even with hardware encoding, a large library takes a long time.

## Testing

```bash
shellcheck convert2hevc.sh tests/smoke.sh
./tests/smoke.sh
```

The smoke test generates two short clips and converts them with libx265,
checking odd filenames, resuming, audio channel count, and that originals
are deleted only on request. CI runs both on every push. The hardware
encoders can't be tested there, since CI has no GPU.

## License

MIT
